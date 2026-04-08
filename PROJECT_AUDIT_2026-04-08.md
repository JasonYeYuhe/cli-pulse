# CLI Pulse 项目深度审查报告

> 审查日期: 2026-04-08
> 审查工具: Claude Opus 4.6 + Gemini 3.1 Pro
> 当前版本: v1.5 (build 25 / versionCode 7)
> **修复状态: 全部 23 个问题已于当日修复完成** (4 CRITICAL + 5 HIGH + 9 MEDIUM + 5 LOW)

---

## 一、项目总览

### 1.1 产品定位

CLI Pulse 是一款多平台 AI 工具用量监控应用，追踪 Claude、Gemini、Copilot、Cursor、Codex 等 20+ AI 供应商的使用数据，提供成本估算、预算告警、团队管理等功能。

### 1.2 平台矩阵

| 平台 | 技术栈 | 状态 | 代码位置 |
|------|--------|------|----------|
| iOS | SwiftUI | 付费上架 App Store | `CLI Pulse Bar/` |
| macOS | SwiftUI + AppKit | ASC 审核中 | `CLI Pulse Bar/` |
| watchOS | SwiftUI | 跟随主 app | `CLI Pulse Bar/CLI Pulse Bar Watch/` |
| Widgets | WidgetKit | 跟随主 app | `CLI Pulse Bar/CLI Pulse Widgets/` |
| Android | Kotlin / Jetpack Compose | 开发中 | `android/` |
| 后端 | PostgreSQL / Supabase | 生产运行中 | `backend/supabase/` |
| Helper | Python 3 | 生产运行中 | `helper/` |
| 文档站 | GitHub Pages | 已上线 | `docs/` |

### 1.3 代码规模

| 语言 | 文件数 | 主要分布 |
|------|--------|----------|
| Swift | ~699 | CLIPulseCore, App targets, codexbar |
| Kotlin | 65 | Android app |
| Python | 12 | Helper CLI + 测试 |
| SQL | 16 | Schema + Migrations + RPC |
| 测试文件 | ~50+ | Swift/Python/Android |

### 1.4 仓库架构

- `origin` → `cli-pulse-private` (私有源码)
- `public` → `cli-pulse` (分发仓库, 仅含 docs/legal)
- 分支策略: `main` 为集成分支, 任务分支按 `功能名` 或 `codex/功能名` 命名

---

## 二、已完成事项

### 2.1 版本里程碑

| 版本 | 内容 |
|------|------|
| v1.0 | 基础架构: 20+ AI 供应商采集器、设备配对、Supabase 后端、iOS/macOS 基础 UI |
| v1.1 | 供应商同步优化、仓库清理、配对体验改进 |
| v1.2 | iOS ↔ Android 版本同步、安全审计 (7轮, 80+ issues) |
| v1.3 | 预算告警、团队管理 UI (创建/邀请/成员管理)、数据导出、可编辑设置 |
| v1.4 | iOS/macOS/watchOS 9大增强、Android 基础版本、GitHub OAuth、菜单栏拖拽调整、Google Play 签名 |
| v1.5 | 精确 Token 统计 (CostUsageScanner)、数据模型重构、定价 API、每日使用量同步、订阅定价追踪 |

### 2.2 基础设施

- [x] CI/CD: GitHub Actions (Swift lint/test, Linux x64/arm64 构建, 发布自动化)
- [x] 安全审计: 7 轮深度审查, 修复 80+ 问题
- [x] 法律合规: Privacy Policy + Terms of Service (2026年4月更新)
- [x] 公私仓库分离: 完整策略文档 + 执行
- [x] 多语言: en, es, ja, ko, zh-Hans 本地化支持
- [x] 文档体系: AGENTS.md, BRANCHING.md, RELEASE_WORKFLOW.md, MERGE_AND_PUBLISH_RULES.md 等 10+ 规范
- [x] Schema 版本管理: v0.2 → v0.10, 含回滚脚本
- [x] RLS (Row Level Security) 全表启用
- [x] OAuth 集成: Google, GitHub, Gemini

### 2.3 供应商支持

已实现 20+ 供应商采集器:
Claude, Codex, Gemini, Copilot, Cursor, Kilo, Kimi, Ollama, OpenRouter, JetBrains AI, Alibaba (通义), Augment, MiniMax, Volcano Engine (火山引擎), Warp, Z.ai, Kiro 等

---

## 三、发现的问题

### 3.1 CRITICAL — 需立即修复

#### C1: Force Unwrap 崩溃风险 (Swift)

**3 处强制解包可能导致生产环境崩溃:**

| 位置 | 代码 | 风险 |
|------|------|------|
| `CodexCollector.swift:37` | `auth.accessToken!` | `accessToken` 是 `String?`，token 刷新失败后仍被强制解包 |
| `GeminiOAuthManager.swift:130` | `comps.url!` | URLComponents 拼装 OAuth URL 后未做 nil 检查 |
| `CostUsageCache.swift:35` | `.urls(for: .cachesDirectory).first!` | 极端情况 FileManager 可能返回空数组 |

**修复建议:** 统一改为 `guard let` + 抛出有意义的错误

#### C2: Android OAuth 深链接无验证

- **位置:** `AndroidManifest.xml:57-63`
- **问题:** `clipulse://auth/callback` 使用 custom scheme, 任何第三方 app 都可伪造此 intent 注入恶意 auth code
- **修复建议:** 迁移到 Android App Links (HTTPS), 添加 `autoVerify="true"` 和 assetlinks.json

#### C3: 数据库 Cost 字段无边界检查

- **位置:** `helper_rpc.sql:137`
- **代码:** `(v_session->>'exact_cost')::numeric`
- **问题:** 直接从 JSON cast 为 numeric, 无上限校验。恶意 payload 可注入天价数据, 触发虚假预算告警
- **修复建议:**
```sql
ALTER TABLE sessions ADD CONSTRAINT chk_cost_bounds
  CHECK (estimated_cost >= 0 AND estimated_cost < 10000);
```

#### C4: 配对码暴力破解防护失效

- **位置:** `migrate_v0.4.sql:34-66`
- **问题:** `failed_attempts` 列已添加, 检查逻辑 (`>= 5` 则拒绝) 已实现, 但**从未在失败时递增计数器**。无论错误多少次, `failed_attempts` 始终为 0
- **修复建议:** 在 `RAISE EXCEPTION 'Invalid pairing code'` 之前添加:
```sql
UPDATE public.pairing_codes SET failed_attempts = failed_attempts + 1
WHERE code = p_pairing_code;
```

---

### 3.2 HIGH — 近期修复

#### H1: 空 Catch 块吞掉错误

- **位置:** `ClaudeCLIPTYStrategy.swift:93`
- **代码:** `} catch {}`
- **问题:** Process 执行查找 `claude` 二进制路径时的错误被完全吞掉, 排查问题时无迹可循
- **修复建议:** 至少 `catch { os_log(.debug, "claude binary lookup failed: %{public}@", error.localizedDescription) }`

#### H2: 数据库清理函数无事务边界

- **位置:** `app_rpc.sql:159-213` (`cleanup_expired_data`)
- **问题:** 循环遍历用户, 对 sessions/alerts/snapshots/provider_quotas 执行多表 DELETE, 无显式事务控制。中途失败导致部分用户数据已删、部分未删
- **修复建议:** 使用 SAVEPOINT 或确保整个函数在单事务中执行 (PL/pgSQL 函数默认在调用者事务中运行, 但应添加异常处理回滚逻辑)

#### H3: evaluate_budget_alerts 无 LIMIT

- **位置:** `app_rpc.sql:244-254`
- **问题:** `GROUP BY s.project` 循环无上限。若用户有上万个项目, 内存和计算开销可能导致函数超时
- **修复建议:** 添加 `LIMIT 500` 或先筛选 TOP N 项目

#### H4: Android 破坏性数据库迁移

- **位置:** `AppModule.kt:42`
- **代码:** `.fallbackToDestructiveMigration(true)`
- **问题:** 任何 Room schema 变更都会**静默清空用户本地缓存**, 无任何提示
- **修复建议:** 仅在 `BuildConfig.DEBUG` 时启用, Release 版实现正规 Migration

#### H5: Release 模式下 Supabase Key 为空字符串

- **位置:** `HelperAPIClient.swift:138-142`
- **代码:**
```swift
#if DEBUG
fatalError("SUPABASE_ANON_KEY missing from Info.plist and environment")
#else
return ""
#endif
```
- **问题:** Release 模式下 key 缺失时返回空字符串, 后续 API 调用全部静默失败
- **修复建议:** Release 模式也应记录错误日志并禁用 API 功能, 或在启动时弹出提示

---

### 3.3 MEDIUM — 计划修复

#### M1: 生产代码残留 print() 语句

共 6 处 `print()` 应替换为 `os.Logger`:

| 文件 | 行号 | 内容 |
|------|------|------|
| `APIClient.swift` | 1090 | `print("[syncProviderQuotas] failed: HTTP \(status)")` |
| `APIClient.swift` | 1093 | `print("[syncProviderQuotas] error: ...")` |
| `APIClient.swift` | 1141 | `print("[syncDailyUsage] failed: HTTP \(status)")` |
| `APIClient.swift` | 1144 | `print("[syncDailyUsage] error: ...")` |
| `DataRefreshManager.swift` | 337 | `print(message)` |
| `ClaudeSourceResolver.swift` | 204 | `print("[ClaudeSourceResolver] \(message)")` |

另有 macOS app 层 `CLIPulseBarApp.swift` 约 5 处 `print()` (LaunchAtLogin 相关)。

#### M2: @unchecked Sendable 并发安全隐患

| 文件 | 风险 |
|------|------|
| `GeminiOAuthManager.swift:58` | 可变 `authSession` 属性跨线程访问 |
| `LocalScanner.swift:13` | Process 执行可能非线程安全 |
| `CostUsageScanner.swift:897` | `ISOFormatterBox` DateFormatter 共享 |

**修复建议:** 使用 actor 隔离或添加锁保护

#### M3: waitUntilExit() 同步阻塞

| 文件 | 行号 |
|------|------|
| `ClaudeCLIPTYStrategy.swift` | 87 |
| `LocalScanner.swift` | 191 |

**问题:** 在 async 上下文中调用同步阻塞的 `task.waitUntilExit()`, 违反 async 执行模型
**修复建议:** 使用 `Process` 的 `terminationHandler` + `withCheckedContinuation`

#### M4: 缺少数据库索引

| 表 | 列 | 原因 |
|----|----|------|
| `sessions` | `device_id` | helper_sync 频繁按 device_id 查询 |
| `team_invites` | `(team_id, email)` | invite_member() 查重依赖此查询 |

> 注: `sessions.provider` 和 `sessions.started_at` 索引已存在 (schema.sql:158-159)

#### M5: 硬编码 UI 字符串未本地化

**Swift 端:**
- `SubscriptionManager.swift:218-228` — "Free", "Pro", "Team" 及其描述
- `AppState.swift:98-102` — "Overview", "Providers", "Sessions", "Alerts", "Settings"

**Android 端:**
- 多个 Composable 文件中直接使用英文字符串, 未移入 `strings.xml`

#### M6: Python Helper 无优雅关机

- **位置:** `cli_pulse_helper.py:202-214`
- **问题:** `daemon()` 函数仅捕获 `KeyboardInterrupt`, 不处理 SIGTERM, 不 flush pending 请求
- **修复建议:** 添加 `signal.signal(SIGTERM, handler)` + 退出前 flush

#### M7: Android ProGuard 规则不完整

- **位置:** `app/proguard-rules.pro`
- **问题:** 仅保留 model 类和 OkHttp, 缺少 Room entities、Hilt 生成代码、Coroutines 等规则
- **风险:** 开启 R8 优化后可能导致反射相关代码被移除

#### M8: Firebase 通知 ID 溢出风险

- **位置:** `PushService.kt:71`
- **代码:** `System.currentTimeMillis().toInt()`
- **问题:** Long → Int 截断可能导致通知 ID 碰撞
- **修复建议:** 使用 `AtomicInteger` 自增或 `abs(UUID.randomUUID().hashCode())`

#### M9: 客户端时间戳未校验

- **位置:** `helper_rpc.sql:141-142`
- **问题:** 客户端发送的 `started_at` 和 `last_active_at` 直接入库, 若客户端时钟偏差大, 会导致图表数据异常
- **修复建议:** 校验客户端时间戳与服务器时间偏差不超过 5 分钟

---

### 3.4 LOW — 改善项

| # | 问题 | 位置 | 说明 |
|---|------|------|------|
| L1 | SandboxFileAccess 潜在死锁 | `SandboxFileAccess.swift:15-24` | `DispatchQueue.main.sync` 从后台线程调用, 有死锁风险 |
| L2 | alerts 表缺少外键约束 | `schema.sql:175-181` | `related_session_id` 等为纯文本, 无引用完整性 |
| L3 | provider_quotas.remaining 缺少 NOT NULL | `schema.sql:337` | 下游查询假设 `remaining >= 0` 会因 NULL 失败 |
| L4 | Helper config 文件权限 | `helper_rpc.sql:56` | 配对后 secret 明文写入 `~/.cli-pulse-helper.json`, 应设 `chmod 0600` |
| L5 | 环境变量名泄露 | `cli_pulse_helper.py:83` | 错误日志暴露 `CLI_PULSE_SUPABASE_ANON_KEY` 变量名 |

---

## 四、功能完善建议

### 4.1 Claude + Gemini 联合推荐

| 优先级 | 功能 | 描述 | 预计收益 |
|--------|------|------|----------|
| **P0** | 实时预算 Kill Switch | 设置硬性日/周限额, 超额推送高优先级告警。防止脚本失控烧钱 | 直接影响用户钱包, 核心卖点 |
| **P0** | OTA 远程配置 | 供应商日志格式变更时可远程更新解析规则, 绕过 App Store 审核周期 | 降低维护成本, 提升稳定性 |
| **P1** | 交互式成本钻取 | 点击用量飙升日期 → 直接展示是哪个项目/模型造成的 (Swift Charts / Vico) | 大幅提升 UX |
| **P1** | 离线优先缓存 | SwiftData + Room 本地缓存, 仪表盘秒开, 后台静默同步 | 改善冷启动体验 |
| **P1** | "吸血任务"检测 | 识别后台持续烧 Token 的无人值守脚本, 在仪表盘标记为异常 | 差异化功能 |
| **P2** | ROI 关联分析 | 集成 Git Hook, 关联 Token 花费与代码产出 (Cost per Commit) | 开发者喜爱的洞察 |
| **P2** | 隐私透明面板 | 专门页面展示离开本机的数据, 展示采集器开源代码 | 建立信任 |
| **P2** | Homebrew 分发 | `brew install cli-pulse-helper` + `brew services` 自动更新 | 降低 onboarding 门槛 |
| **P2** | 客户端错误追踪 | Sentry / 自建, 供应商格式变更时主动告警 | 运维效率 |
| **P3** | 统一设计令牌 | JSON 定义色彩/字体/间距, 构建时生成 Swift/Kotlin 常量 | 品牌一致性 |
| **P3** | 共享业务逻辑层 | 考虑 KMP 或 Rust 共享成本计算/数据模型, 减少跨平台维护 | 长期降本 |
| **P3** | 会计导出报表 | 一键 PDF/CSV 按项目分列费用, 适用于报税或客户账单 | 企业用户需求 |

### 4.2 Gemini 补充的行业建议

1. **格式脆性防护:** 上游供应商 (Claude, Cursor, Copilot) 会不加通知地更改日志格式。建议解析规则可通过后端远程推送更新, 无需用户手动更新 daemon
2. **时钟偏移与去重:** 多设备同步数据到 Supabase 时, 使用 `device_id + timestamp + model` 的幂等 upsert 防止重复计数
3. **电池优化:** 文件轮询 (`ps` 查进程) 是耗电大户。建议使用 `FSEvents` (macOS) / `watchdog` (Python) 替代循环轮询
4. **平台功能差距:** Android 版落后 iOS 较多, 跨平台用户期望功能对等, 可能影响评分

---

## 五、待做事项

### 5.1 近期 — 本月 (2026年4月)

- [ ] **修复 C1:** 3 处 force unwrap → guard let
- [ ] **修复 C2:** Android OAuth 深链接迁移到 App Links
- [ ] **修复 C3:** sessions 表添加 cost 边界 CHECK 约束
- [ ] **修复 C4:** register_helper 添加 failed_attempts 递增逻辑
- [ ] **修复 H1:** ClaudeCLIPTYStrategy 空 catch → os_log
- [ ] **修复 H4:** Android Room 迁移改为正规 Migration (Release 模式)
- [ ] **修复 H5:** Release 模式 Supabase key 缺失处理
- [ ] iOS v1.5 完成 App Store 审核
- [ ] macOS v1.5 重新上传 ASC

### 5.2 中期 — 本季度 (2026 Q2)

- [ ] Google Play 正式发布 Android 版
- [ ] Android 功能追平: 团队管理、数据导出、预算告警
- [ ] 替换所有 `print()` 为 `os.Logger` (M1)
- [ ] 修复 3 处 `@unchecked Sendable` (M2)
- [ ] 补全数据库索引: sessions.device_id, team_invites.email (M4)
- [ ] 本地化硬编码 UI 字符串 (M5)
- [ ] 实现离线优先缓存架构 (P1)
- [ ] 实现交互式成本钻取图表 (P1)
- [ ] 完善 Android ProGuard 规则 (M7)

### 5.3 长期 — Q3-Q4 2026

- [ ] OTA 远程配置系统 (P0)
- [ ] Homebrew 分发 Python Helper (P2)
- [ ] Sentry 客户端错误追踪 (P2)
- [ ] 隐私透明面板 (P2)
- [ ] ROI / 生产力关联分析 (P2)
- [ ] 共享业务逻辑层 KMP/Rust 评估 (P3)
- [ ] 会计导出报表 (P3)

---

## 六、各模块健康度评估

### 6.1 平台状态

| 平台 | 版本 | 状态 | 健康度 | 主要风险 |
|------|------|------|--------|----------|
| iOS | v1.5 build 25 | 付费上架, 审核中 | **A-** | 3 处 force unwrap |
| macOS | v1.5 build 25 | ASC 上传中 | **A-** | 同上 + print 清理 |
| watchOS | v1.5 | 跟随主 app | **B+** | 功能较少 |
| Android | versionCode 7 | 开发中 | **B** | 破坏性迁移 + 深链接安全 |
| 后端 | schema v0.10 | 生产运行中 | **B+** | 限速失效 + 事务缺失 |
| Helper | — | 生产运行中 | **B+** | 无优雅关机 + 超时处理 |

### 6.2 代码质量

| 维度 | 评分 | 说明 |
|------|------|------|
| 代码整洁度 | **A** | 仅 2 个 TODO 注释, 结构清晰 |
| 测试覆盖 | **B+** | 50+ 测试文件, 但缺少集成测试 |
| 文档完整度 | **A** | 10+ 规范文档, 评级优秀 |
| 安全性 | **B** | RLS 全表启用, 但存在 4 个 CRITICAL |
| CI/CD | **A** | GitHub Actions, 多平台构建 |
| 本地化 | **B-** | 框架已有, 但 Android 端和部分 Swift 代码仍有硬编码 |

### 6.3 风险汇总

| 严重级别 | 数量 | 分布 |
|----------|------|------|
| CRITICAL | 4 | Swift 1, Android 1, Backend 2 |
| HIGH | 5 | Swift 1, Android 1, Backend 2, Swift/Backend 1 |
| MEDIUM | 9 | Swift 3, Android 2, Backend 3, Python 1 |
| LOW | 5 | Swift 1, Backend 3, Python 1 |

---

## 七、总结

CLI Pulse 项目整体质量**良好偏上**, 代码库整洁 (仅 2 个 TODO)、文档体系完善 (A 级)、安全审计历经 7 轮。主要风险集中在:

1. **3 处 Swift force unwrap** — 最可能导致用户可见崩溃
2. **Android OAuth 安全** — custom scheme 可被伪造
3. **后端限速形同虚设** — 配对码暴力破解无实际防护
4. **Cost 字段无边界** — 恶意 payload 可注入异常数据

建议优先修复 4 个 CRITICAL 和 5 个 HIGH 问题后, 再推进 P0/P1 新功能 (实时预算告警、OTA 配置、离线缓存)。Android 版功能追平是本季度的重点工作。

---

*本报告由 Claude Opus 4.6 主导审查, Gemini 3.1 Pro 提供跨平台架构和行业实践建议。所有问题均经人工验证代码行号和上下文。*
