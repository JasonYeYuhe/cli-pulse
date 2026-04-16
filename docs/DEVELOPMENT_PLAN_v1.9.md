# CLI Pulse v1.9 开发计划书

> 审查日期: 2026-04-16 | 当前版本: v1.8 (Build 27, 已提交 App Store 审核)
> Codex Review: 已通过审查并修正（2026-04-16）

---

## 一、项目健康诊断

### 当前状态: 稳定，可发版

| 维度 | 状态 | 详情 |
|------|------|------|
| macOS 编译 | ✅ | BUILD SUCCEEDED (全 scheme) |
| Swift 测试 | ✅ | 186/186 通过 |
| Python 测试 | ✅ | 27/27 通过 |
| Android 编译 | ⚠️ | 开发机无 Java，CI 正常 |
| App Store | ⏳ | v1.8 Build 27 审核中 |
| Provider 覆盖 | ✅ | 26 个 Provider（含新增 GLM）|

### 发现的问题（按优先级排列，经 Codex 验证）

#### P1 — 质量问题

1. **Android 数据层缺少单元测试**
   - 66 个 Kotlin 文件仅 8 个测试文件 + 1 个 Rule（全在 `ui/` 包下）
   - `data/collector/`、`data/remote/`、`data/local/` 零覆盖
   - Room 目前版本 1 无迁移，但 CollectorManager 逻辑需验证
   - **修复**: 增加数据层测试（CollectorManager + 5 个核心 Collector）

2. **UI 硬编码字符串绕过 i18n**
   - iOS: TeamView.swift (8处), iOSLoginView.swift (2处)
   - Android: SettingsScreen.kt (15+处), TeamScreen.kt, SubscriptionScreen.kt
   - 平台间本地化覆盖不一致：Android 缺少 Spanish (`values-es/`)，Swift 有 `es.lproj`
   - **修复**: 迁移到各平台 L10n 系统 + 对齐语言矩阵

3. **Android 平台功能缺失（与 iOS 不对齐）**
   - 缺少: 团队角色变更 UI、待处理邀请列表、导出功能入口
   - `ExportUtil.kt` 存在但未被任何 UI/ViewModel 调用（Codex 验证: 无 caller）
   - 注意: Android 已有团队列表/成员列表/创建/邀请/移除功能，差距比预期小
   - **修复**: 补齐 3 项缺失 UI

#### P2 — 改进项

4. **错误提示不统一** — Android 无全局 Snackbar 系统（各页面内联处理），macOS 在 MenuBarView 处理
5. **Accessibility 标签缺失** — Android 多处 `contentDescription = null`，Swift 缺少 `accessibilityLabel`
6. **macOS Settings 缺少 Webhook 配置 UI** — iOS/Android 已有，macOS SettingsTab.swift 遗漏

> **Codex 修正**: 原计划中 "android/local.properties 未 gitignore" 为误报（已在 `android/.gitignore` 中）；
> "README 仅覆盖 Swift 和 Python" 为误报（已包含 Android 指令）。

---

## 二、v1.9 新功能规划

### 功能 A: 成本预测与智能预算

**目标**: 根据历史用量趋势，预测本月剩余花费。

**前置条件** (Codex 发现):
- Android 缺少 `DailyUsage` 客户端模型/Repository/ViewModel — 需先补齐
- `AlertGenerator.swift` 仅限 macOS — 预测告警需走跨平台路径（后端 RPC 或 helper）

**实现范围**:
- Phase 1 (Apple only): 基于 `daily_usage_metrics` 客户端线性回归，复用现有 `APIClient.fetchDailyUsage`
- Phase 2 (Android): 补齐 DailyUsage 数据管道后接入
- 在 Overview Dashboard 显示 "月末预计花费" 卡片（标注"预估"+ 置信区间）
- 无需 `forecast_cache` 表 — 客户端计算足够，性能问题出现后再加

**涉及文件**:
- 新建 `CostForecastEngine.swift` (CLIPulseCore)
- 新建 `CostForecastCard.swift` (macOS/iOS OverviewTab)
- 修改 Android: 先新建 `DailyUsageRepository.kt` + `DailyUsageViewModel.kt`，再接入预测
- 暂不修改 AlertGenerator（告警走后端 RPC 或 helper 而非 macOS-only 路径）

**工期**: 3-4 天（Phase 1 Apple: 2 天，Phase 2 Android 管道: 1-2 天）

### 功能 B: Slack/Webhook 告警增强

**目标**: 增强现有 Webhook 为 Slack-friendly 格式 + 事件过滤。

**现状** (Codex 验证):
- `backend/supabase/functions/send-webhook/index.ts` 已存在
- iOS/Android 已有 Webhook URL 配置和测试按钮
- 缺失: macOS Settings 无 Webhook UI、无事件过滤、无 Slack Block Kit 格式

**实现范围** (精简后):
- 增强 `backend/supabase/functions/send-webhook/index.ts` — Slack Block Kit payload
- 新增 `webhook_event_filter` 字段到 `user_settings` 表 + 双平台模型
- 补齐 macOS SettingsTab.swift 的 Webhook 配置 UI
- 移除: "测试按钮" 已在 iOS/Android 存在，无需重复

**涉及文件**:
- 修改 `backend/supabase/functions/send-webhook/index.ts`
- 新增 Supabase migration: `webhook_event_filter` 字段
- 修改 `SettingsTab.swift` (macOS) — 添加 Webhook section
- 修改 `SettingsSnapshot` (双平台) — 新增 filter 字段

**工期**: 2-3 天

### 功能 C: 每模型成本分析图表

**目标**: 可视化各模型的花费占比。

**现状** (Codex 发现):
- Apple 端 `DataRefreshManager.swift` 已计算 `costByModel`
- macOS `OverviewTab.swift` 已有基础模型分析展示
- Android 无 chart 库依赖，需先选型引入

**实现范围**:
- Apple: 扩展现有 `costByModel` 为可交互饼图/柱状图，加入时间范围筛选
- Android: 引入轻量 chart 库（如 Vico），补齐 DailyUsage 数据管道后接入
- 可按今日/本周/本月筛选

**涉及文件**:
- 修改 `OverviewTab.swift` (macOS) — 扩展现有模型分析
- 修改 `CLI Pulse Bar iOS/` 对应 View — 接入模型图表
- Android: 新建 `ModelBreakdownChart.kt`，修改 `build.gradle.kts` 添加 chart 依赖
- 前置: Android DailyUsage 管道（与功能 A 共享）

**工期**: 2-3 天（Apple 1 天，Android 需依赖 DailyUsage 管道 1-2 天）

### 功能 D: PDF 月度报告导出

**目标**: 一键生成月度使用/花费报告 PDF。

**注意** (Codex 发现):
- `ExportService.swift` 是 CLIPulseCore 共享代码，含 watchOS — PDFKit 需 `#if !os(watchOS)` 平台隔离
- Android 无 chart 渲染层，PDF 内含图表需额外工作
- 团队报告数据管道 Android 侧不完整

**实现范围** (分阶段):
- **Phase 1 (Apple only)**: PDFKit 生成，平台隔离在 `#if canImport(PDFKit)`，包含月度总结 + Provider 分布 + 成本趋势
- **Phase 2 (Android)**: 待 Android chart 库和 DailyUsage 管道就绪后实现
- 团队报告暂缓（Android 团队数据管道不完整）

**涉及文件**:
- 新建 `PDFReportGenerator.swift` (macOS/iOS，`#if canImport(PDFKit)` 隔离)
- 修改 ExportService.swift — 新增 `.pdf` 格式选项（平台隔离）
- Android Phase 2: 新建 `PdfReportGenerator.kt` (依赖 chart 库)

**工期**: Phase 1: 2-3 天，Phase 2: 2 天（待前置条件）

### 功能 E: 交互式 Widget 增强

**目标**: 将现有 StaticConfiguration Widget 升级为 AppIntent 交互式。

**现状** (Codex 发现):
- 当前 Widget 全部是 `StaticConfiguration`
- `ProviderUsageWidget` 已是单 Provider 详情 Widget（无需新建）
- AppIntent 交互接入比预想复杂，需要处理 Widget Timeline 刷新

**实现范围** (精简):
- 将现有 Widget 升级为 `AppIntentConfiguration`
- 添加 "切换 Provider" 交互按钮
- 添加 "刷新数据" 交互按钮
- 移除: "单 Provider Widget" 已存在

**涉及文件**:
- 修改 `CLI Pulse Widgets/` — AppIntent 声明 + Configuration 迁移
- 修改 `CodexBarWidgetProvider.swift` → `AppIntentConfiguration`

**工期**: 2-3 天（比原预估增加，AppIntent 接线复杂度高）

---

## 三、实施路线图（修正后）

> 原则: 修复先于功能，管道先于展示，Apple 先于 Android（验证路径更快）

### Sprint 1: 修复 + 管道基建（2-3 天）
- [ ] Commit GLM Provider 集成
- [ ] Android 数据层测试（CollectorManager + 5 个 Collector）
- [ ] Android DailyUsage 数据管道（Model + Repository + ViewModel）— 功能 A/C 前置
- [ ] 补齐 macOS SettingsTab Webhook UI（功能 B 前置）

### Sprint 2: 本地化 + 平台对齐（2-3 天）
- [ ] i18n 迁移: 双平台硬编码字符串 → L10n/strings.xml
- [ ] Android 语言矩阵对齐（新增 `values-es/`）
- [ ] Android 平台功能补齐（导出入口、待处理邀请、角色变更 UI）
- [ ] Accessibility 标签（Android contentDescription + Swift accessibilityLabel）

### Sprint 3: 成本分析 + Webhook（3-4 天）
- [ ] 功能 A Phase 1: Apple 成本预测引擎 + Dashboard 卡片
- [ ] 功能 C: 模型成本分析图表（Apple 扩展 + Android 新建）
- [ ] 功能 B: Slack/Webhook 增强（Edge Function + 事件过滤 + macOS UI）
- [ ] 功能 A Phase 2: Android 成本预测接入

### Sprint 4: 导出 + Widget + 发版（3-4 天）
- [ ] 功能 D Phase 1: Apple PDF 报告导出
- [ ] 功能 E: Widget 交互式升级
- [ ] 功能 D Phase 2: Android PDF 导出（如管道就绪）
- [ ] 错误提示统一化（Android Snackbar 系统）
- [ ] v1.9 发版准备 + 全平台回归测试

---

## 四、技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 智谱 finance API 响应格式不确定 | GLM Collector 需调整 | 防御性解析 + GLM_API_HOST 覆盖 |
| Android DailyUsage 管道工作量超预期 | 阻塞功能 A/C/D | Sprint 1 优先完成，阻塞时先发 Apple-only |
| PDF 生成 watchOS 平台隔离 | ExportService 共享代码引入编译错误 | `#if canImport(PDFKit)` 严格隔离 |
| Android chart 库选型 | 引入新依赖增加包体积 | 选择轻量库 Vico (~200KB) |
| App Store v1.8 审核不通过 | 发版延迟 | 已修复全部拒绝原因，候选方案就绪 |
| 成本预测精度低 | 用户信任度下降 | 标注"预估"、显示置信区间、仅展示不做自动化决策 |
| AlertGenerator 仅 macOS | 预测告警无法跨平台 | 走后端 RPC 或 helper daemon 路径 |
| macOS Webhook UI 从未测试 | 新增 Settings 区域可能回归 | 与现有 iOS/Android UI 保持 1:1 对齐 |

---

## 五、成功指标

- [ ] macOS + iOS + Android 全平台编译通过
- [ ] Swift 测试 > 200（当前 186）
- [ ] Android 测试 > 20（当前 8）
- [ ] Android DailyUsage 管道端到端可用
- [ ] 成本预测偏差 < 25%（基于 7 天回测）
- [ ] Webhook Slack 消息格式正确渲染
- [ ] PDF 报告在 iPhone 12 上生成时间 < 5 秒
- [ ] 全部 UI 字符串走 L10n（0 硬编码）
- [ ] Android/iOS 语言矩阵 100% 对齐

---

## 六、Codex Review 修正记录

| 原计划内容 | Codex 发现 | 修正 |
|-----------|-----------|------|
| P0: local.properties 未 gitignore | 误报 — 已在 `android/.gitignore` 中 | 删除该条目 |
| P2: README 仅覆盖 Swift/Python | 误报 — 已包含 Android | 删除该条目 |
| 功能 A: forecast_cache 表 | 过早优化 | 改为客户端计算，按需加缓存 |
| 功能 A: AlertGenerator 触发 | macOS-only，无法跨平台 | 改走后端 RPC/helper |
| 功能 B: 新增测试按钮 | iOS/Android 已有 | 移除重复工作 |
| 功能 B: 后端路径 | 写错为 `supabase/functions/` | 修正为 `backend/supabase/functions/` |
| 功能 C: CostHistoryChartMenuView | 属于 codexbar target，非 shipping target | 改为扩展 OverviewTab + 现有 costByModel |
| 功能 C: Android 图表 | 无 chart 依赖 | 新增 chart 库选型 + 引入步骤 |
| 功能 D: ExportService + PDFKit | 共享至 watchOS，需平台隔离 | 加 `#if canImport(PDFKit)` |
| 功能 D: Android PDF | 缺 chart 层和团队数据管道 | 拆分为 Phase 2，依赖前置条件 |
| 功能 E: 单 Provider Widget | ProviderUsageWidget 已存在 | 移除重复，聚焦交互升级 |
| Sprint 排序 | 功能先于修复/管道 | 修正为: 管道先于功能，修复先于新增 |
| macOS Webhook UI | 计划未提及缺失 | 新增为 P2 问题 + Sprint 1 前置 |
