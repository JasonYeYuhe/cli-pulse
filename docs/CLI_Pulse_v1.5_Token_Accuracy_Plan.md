# CLI Pulse v1.5 技术方案：Token 精准计量、订阅费追踪与历史成本分析

**版本:** 1.1
**日期:** 2026-04-07
**作者:** Claude + Gemini 3.1 Pro
**状态:** Draft — 待确认

---

## 1. 背景与问题

CLI Pulse v1.4.1 已发布全平台（macOS/iOS/watchOS/Android），核心 quota/tier 追踪功能正常工作。但与上游 CodexBar 对比，存在以下差距：

### 差距 1：Token 统计不精确
- **CLI Pulse**：`LocalScanner` 通过 `ps` 检测进程，用 CPU + 运行时长估算 token 量 → 偏差很大
- **CodexBar**：直接解析 `~/.codex/sessions/YYYY/MM/DD/*.jsonl` 和 Claude 日志，获取精确的 `input_tokens + output_tokens + cached_tokens`
- 导致 `today_usage == week_usage`（没有历史数据），Cost Summary 全显示 `<$0.01`

### 差距 2：无历史成本追踪
- CodexBar 有 `CostUsageScanner` + `CostUsageCache` + `CostUsagePricing` 完整链路
- CLI Pulse 只有当前快照，无按天/按模型的成本分析

### 差距 3：Xcode 控制台错误（轻微）
- `NSSecureCoding` 警告：App Group UserDefaults IPC 序列化未指定具体类型
- `os.log` decode range 错误：Logger 字符串插值路径过长

---

## 2. 目标

1. **精准 Token 计量**：从本地 JSONL 日志获取真实 token 数据
2. **历史按日分析**：支持 daily/weekly/monthly breakdown，按模型展示
3. **跨设备同步**：历史数据上传 Supabase，手机也能看
4. **修复控制台警告**

---

## 3. 实施计划

### 阶段一：集成 CostUsageScanner（2-3 天）

**目标**：替换 LocalScanner 的估算逻辑，改为解析本地日志获取精确 token 数据。

**步骤**：

1. **新增 `CostUsageScanner.swift`**
   - 路径：`CLIPulseCore/Sources/CLIPulseCore/CostUsageScanner.swift`
   - 参考：`codexbar/Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift`
   - 扫描路径：
     - Codex: `~/.codex/sessions/YYYY/MM/DD/*.jsonl`
     - Claude: `~/Library/Application Support/Claude/projects/*/sessions/*.jsonl`
   - 解析逻辑：
     ```
     每行 JSON → 提取 type == "event_msg" && payload.type == "token_count"
     → 取 total_token_usage.{input_tokens, cached_input_tokens, output_tokens}
     → 增量 delta 计算（避免重复计数）
     → 按 timestamp 归入日期桶
     ```

2. **新增 `CostUsageCache.swift`**
   - 路径：`CLIPulseCore/Sources/CLIPulseCore/CostUsageCache.swift`
   - 参考：`codexbar/Sources/CodexBarCore/Vendored/CostUsage/CostUsageCache.swift`
   - 每个文件记录：`mtime`, `size`, `parsedBytes`, `lastModel`, `lastTotals`
   - 缓存位置：`~/Library/Caches/CLIPulse/cost-usage/`
   - 增量扫描：只解析 `parsedBytes` 之后的新内容

3. **集成到 DataRefreshManager**
   - 在 `runCollectors()` 之后调用 `CostUsageScanner.scan()`
   - 将精确 token 数据合并到 `CollectorResult`
   - 保留现有 API collector 的 quota/tier 数据（它们的 remaining% 比本地日志更准确）

**不改的**：
- LocalScanner 保留用于进程检测（活跃会话数、进程名）
- API collectors 保留用于 quota/remaining/tier 数据
- CostUsageScanner 只补充精确的 token 和成本数据

### 阶段二：数据模型重构 + 成本计算（2-3 天）

**目标**：扩展数据模型支持按日历史数据，引入模型定价表。

1. **扩展数据模型** (`Models.swift`)
   ```swift
   struct DailyUsage: Codable, Identifiable {
       var id: String { "\(date)-\(provider)-\(model)" }
       let date: String           // "2026-04-07"
       let provider: String       // "Codex", "Claude"
       let model: String          // "gpt-4", "claude-sonnet"
       let inputTokens: Int
       let cachedTokens: Int
       let outputTokens: Int
       let cost: Double
   }
   ```

2. **新增定价表** (`Pricing.swift`)
   - 路径：`CLIPulseCore/Sources/CLIPulseCore/Pricing.swift`
   - 参考：`codexbar/Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift`
   - 按模型 per-million-token 定价
   - 初版硬编码，后续可从服务器拉取

3. **修改 ProviderUsage**
   - 新增 `dailyBreakdown: [DailyUsage]` 字段（可选）
   - `today_usage` / `week_usage` 从 `dailyBreakdown` 聚合计算
   - `estimated_cost_today` / `estimated_cost_week` 从定价表精确计算

4. **UI 适配**
   - OverviewTab Cost Summary 显示真实成本而非 `<$0.01`
   - 新增 7 天趋势图（用现有 `trend` sparkline 组件）

### 阶段三：历史数据同步到 Supabase（2-3 天）

**目标**：手机端也能看到 macOS 采集的精确历史数据。

1. **新增 Supabase 表**
   ```sql
   CREATE TABLE daily_usage_metrics (
       user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
       metric_date DATE NOT NULL,
       provider TEXT NOT NULL,
       model TEXT NOT NULL,
       input_tokens BIGINT NOT NULL DEFAULT 0,
       cached_tokens BIGINT NOT NULL DEFAULT 0,
       output_tokens BIGINT NOT NULL DEFAULT 0,
       cost NUMERIC(10,6) NOT NULL DEFAULT 0,
       updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
       PRIMARY KEY (user_id, metric_date, provider, model)
   );
   ALTER TABLE daily_usage_metrics ENABLE ROW LEVEL SECURITY;
   CREATE POLICY "Users own metrics" ON daily_usage_metrics
       FOR ALL USING (auth.uid() = user_id);
   ```

2. **新增 RPC 函数** (`app_rpc.sql`)
   - `upsert_daily_usage(metrics jsonb)` — 批量 upsert
   - `get_daily_usage(days int)` — 获取最近 N 天数据

3. **客户端同步**
   - `APIClient.syncDailyUsage([DailyUsage])` — POST upsert
   - 在 `DataRefreshManager` 中，CostUsageScanner 完成后非阻塞上传
   - 只同步已完成的日期（T-1 及更早），当天数据持续变化不上传
   - iOS/Android 端通过 `get_daily_usage` RPC 拉取展示

### 阶段四：订阅费追踪（1-2 天）

**目标**：让用户看到真实的 AI 月度总支出 = 订阅费 + 使用费，而不仅仅是 token 成本。

**动机**：订阅费才是大头。Claude Max 20x = $200/月，OpenAI Plus = $20/月，Cursor Pro = $20/月。不算这些，Cost Summary 永远显示 `<$0.01`，毫无参考价值。

1. **新增 `SubscriptionPricing.swift`**
   - 路径：`CLIPulseCore/Sources/CLIPulseCore/SubscriptionPricing.swift`
   - 静态定价表，按 `(provider, plan_type)` 查月费：
     ```swift
     public enum SubscriptionPricing {
         public static func monthlyCost(provider: String, plan: String?) -> Double? {
             // 返回 nil 表示免费或未知
         }

         static let table: [String: [String: Double]] = [
             "Claude": ["Max 5x": 100, "Max 20x": 200, "Pro": 20, "Team": 30],
             "Codex":  ["Plus": 20, "Pro": 200, "Team": 30],
             "Gemini": ["Pro": 20, "Advanced": 20, "Business": 30],
             "Cursor": ["Pro": 20, "Business": 40],
             "Copilot": ["Individual": 10, "Business": 19],
             "JetBrains AI": ["Pro": 10],
             "Warp": ["Pro": 15, "Team": 22],
             "Augment": ["Dev": 50],
             // ... 可扩展
         ]
     }
     ```

2. **扩展 `CostSummary` 模型**
   - 文件：`ProviderConfig.swift`
   - 新增字段：
     ```swift
     public struct CostSummary: Sendable {
         // 现有
         public let todayTotal: Double
         public let thirtyDayTotal: Double
         // 新增
         public let subscriptionTotal: Double  // 所有活跃 provider 的月订阅费合计
         public let subscriptionByProvider: [(provider: String, plan: String, monthlyCost: Double)]
         public let grandTotal: Double         // subscriptionTotal + thirtyDayTotal
     }
     ```

3. **修改 `updateCostSummary()`**
   - 文件：`AppState.swift` (line ~622)
   - 遍历 `providers`，用 `SubscriptionPricing.monthlyCost(provider, plan_type)` 查订阅费
   - 只计入 `isEnabled` 的 provider

4. **UI 展示**
   - **OverviewTab `costSection`**：在 Today / 30 Day 下面新增 "Monthly Subscriptions" 行
   - 显示样式：
     ```
     ┌─────────────────────────────────┐
     │ 💰 Cost Summary                │
     │ Today         30 Day Est.      │
     │ <$0.01        <$0.01           │
     │                                 │
     │ 📋 Subscriptions    $240/mo    │
     │ · Claude Max 20x    $200       │
     │ · Codex Plus         $20       │
     │ · Cursor Pro         $20       │
     │                                 │
     │ Total Monthly       ~$240      │
     └─────────────────────────────────┘
     ```
   - iOS `iOSProvidersTab` 和 macOS `ProvidersTab` 的 provider 卡片也显示月费标签
   - 当 `showCost == false` 时隐藏

5. **数据来源**
   - `plan_type` 已由各 collector 通过 API 自动获取（如 Claude 返回 "Max"，Codex 返回 "Plus"）
   - 用户也可以在 Settings 手动指定/覆盖 plan（v1.6 再做）

### 阶段五：修复 Xcode 控制台警告（1 天）

1. **NSSecureCoding 警告**
   - 文件：`HelperIPC.swift`, `AppState.swift`
   - 原因：App Group UserDefaults 跨进程访问时 XPC 层校验序列化对象
   - 修复：改用纯 `Data`/`JSONEncoder` 序列化，避免 `NSKeyedArchiver`

2. **os.log decode range 错误**
   - 文件：`SandboxFileAccess.swift`, `BookmarkManager.swift`, `CredentialBridge.swift`
   - 原因：Logger 字符串插值中的长路径触发格式化缓冲区溢出
   - 修复：添加 `privacy: .public` 标注
     ```swift
     // 之前
     logger.debug("No bookmark for: \(path)")
     // 之后
     logger.debug("No bookmark for: \(path, privacy: .public)")
     ```

---

## 4. 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 日志格式变更（Codex/Claude 更新） | 解析失败 | 健壮错误处理 + 格式版本检测 + 回退到 API 数据 |
| 首次全量扫描慢（历史日志大） | 启动卡顿 | 后台线程 + 增量缓存 + 进度提示 |
| 模型定价变化 | 成本计算不准 | 初版固定表，v1.6 可从服务器拉取带时间范围的价格表 |
| Sandbox 限制（无法读日志） | 功能不可用 | BookmarkManager 引导用户授权 + Helper daemon 读取 |

## 5. 时间线

| 阶段 | 内容 | 预估工时 |
|------|------|----------|
| Phase 1 | CostUsageScanner 集成（精准 token） | 2-3 天 |
| Phase 2 | 数据模型 + 定价表 + UI | 2-3 天 |
| Phase 3 | Supabase 历史数据同步 | 2-3 天 |
| Phase 4 | 订阅费追踪 + UI | 1-2 天 |
| Phase 5 | 控制台警告修复 | 1 天 |
| 测试 & buffer | 集成测试 | 2 天 |
| **总计** | | **10-14 工作日** |

## 6. 关键参考文件

### CodexBar（上游参考）
- `codexbar/Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift` — 日志扫描核心
- `codexbar/Sources/CodexBarCore/Vendored/CostUsage/CostUsageCache.swift` — 增量缓存
- `codexbar/Sources/CodexBarCore/CostUsageModels.swift` — 数据模型
- `codexbar/Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift` — Claude OAuth 窗口

### CLI Pulse（当前代码）
- `CLIPulseCore/Sources/CLIPulseCore/LocalScanner.swift` — 进程检测（保留）
- `CLIPulseCore/Sources/CLIPulseCore/Models.swift` — ProviderUsage 模型（待扩展）
- `CLIPulseCore/Sources/CLIPulseCore/Collectors/` — API collectors（保留）
- `CLIPulseCore/Sources/CLIPulseCore/DataRefreshManager.swift` — 刷新编排（集成点）
