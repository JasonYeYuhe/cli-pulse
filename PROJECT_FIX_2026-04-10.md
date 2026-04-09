# CLI Pulse 修复存档 — 2026-04-10

> 修复工具: Claude Opus 4.6 + Codex (GPT) 交叉审查
> 基于版本: v1.7 (commit 7103b18)
> 测试结果: Swift 186/186 pass, Python 27/27 pass

---

## 修改文件清单 (12 files, +91 -40)

| # | 文件 | 修改类型 | 说明 |
|---|------|----------|------|
| 1 | `CLI Pulse Bar/CLI Pulse Bar/CLIPulseBarApp.swift` | 改善 | 5 处 `print()` → `os.Logger` |
| 2 | `CLI Pulse Bar/CLI Pulse Widgets/WidgetDataProvider.swift` | 修复 | 5 处 force unwrap → safe fallback |
| 3 | `CLI Pulse Bar/CLIPulseCore/Tests/.../ClaudeRuntimeVerificationTest.swift` | 同步 | plan_type "Max" → "Max 20x" |
| 4 | `CLI Pulse Bar/CLIPulseCore/Tests/.../ClaudeStrategyTests.swift` | 同步 | plan type 映射测试更新 |
| 5 | `CLI Pulse Bar/CLIPulseCore/Tests/.../OllamaCollectorTests.swift` | 同步 | testAlwaysAvailable → testAvailabilityDependsOnServer |
| 6 | `CLI Pulse Bar/CLIPulseCore/Tests/.../ProviderFixtureRegressionTests.swift` | 同步 | plan_type "Max" → "Max 20x" |
| 7 | `CLI Pulse Bar/codexbar/.../PlanUtilizationHistoryChartMenuView.swift` | 修复 | `points.first!` → guard let |
| 8 | `android/app/src/main/AndroidManifest.xml` | 安全 | 添加 App Links HTTPS intent-filter |
| 9 | `android/.../MainActivity.kt` | 安全 | 支持 HTTPS+自定义 scheme 双回调, state 校验 |
| 10 | `android/.../SupabaseClient.kt` | 安全 | redirect_to → HTTPS, 添加 state 参数 |
| 11 | `android/.../AppModule.kt` | 安全 | Release 禁用破坏性迁移, Debug 保留 |
| 12 | `android/.../LoginViewModel.kt` | 同步 | Pair → Triple 返回类型 |
| 13 | `android/.../LoginScreen.kt` | 安全 | Triple 解构 + 设置 expectedOAuthState |

**新建文件:**
| 文件 | 说明 |
|------|------|
| `docs/.well-known/assetlinks.json` | Android App Links 验证 (SHA256: B5:AB:83:64:...) |

---

## 修复详情

### P0 — 崩溃修复

#### F1: 4 个 Swift 测试失败
- **根因**: v1.7 的 `ClaudeResultBuilder` 新增了 Max 5x/20x 计划区分，测试期望值未同步
- **修复**: 更新 4 个测试文件中的期望值
- **验证**: 186 tests, 0 failures

#### F2: Widget 5 处 force unwrap
- **根因**: `WidgetData.preview.providers.first!` 在 preview 数据为空时崩溃
- **修复**: 引入 `fallbackProvider` 静态常量 + `previewProvider` 计算属性, nil-coalescing
- **验证**: 无 `.first!` 残留 (`grep` 确认)

#### F3: Chart `points.first!`
- **根因**: 图表数据为空时强制解包导致崩溃
- **修复**: `guard let firstPoint = points.first else { return [] }`

### P1 — 安全修复

#### F4: Android OAuth CSRF + 深链接劫持
- **根因**: (1) 使用自定义 scheme `clipulse://` 可被任意 app 拦截 (2) 无 `state` 参数防 CSRF
- **修复**:
  - `SupabaseClient.oauthAuthorizeUrl()` → 返回 Triple(url, verifier, state), redirect_to 改为 HTTPS
  - `AndroidManifest.xml` → 添加 `android:autoVerify="true"` 的 HTTPS intent-filter
  - `MainActivity.handleOAuthDeepLink()` → 同时接受 HTTPS 和自定义 scheme, 校验 state
  - `docs/.well-known/assetlinks.json` → 真实 SHA256 指纹
- **Codex 确认**: "oauthAuthorizeUrl() sends no state" → 已修复

#### F5: Android Room 破坏性迁移
- **根因**: `fallbackToDestructiveMigration(true)` 在所有 build 下静默清空缓存
- **修复**: Debug 保留 fallback, Release 不启用 (强制编写 Migration)
- **验证**: 无 `fallbackToDestructiveMigration` 在 release 路径

#### F6: macOS print() → Logger
- **修复**: 5 处 `print()` → `Logger(subsystem: "com.clipulse.bar", category: "AppLifecycle")`
- **验证**: CLIPulseBarApp.swift 中无 `print(` 残留

### 已确认不需要修复的项 (Codex 验证)

| 原问题 | 实际状态 |
|--------|----------|
| Python SIGTERM 处理缺失 | **已存在** — SIGTERM + SIGHUP handler 在 cli_pulse_helper.py:211 |
| DB 索引缺失 (sessions.device_id) | **已存在** — schema.sql:158, migrate_v0.11.sql:134 |
| @unchecked Sendable 3 处 | **有保护** — MainActor / NSLock / 无可变状态, 降级 P3 |
| Android 功能差距 (团队/告警) | **已有基础** — TeamScreen, AlertsScreen 已实现, 只缺邀请角色+导出 UI |

---

## 验证清单

- [x] `swift test` — 186 tests, 0 failures
- [x] `pytest` — 27 tests, 0 failures
- [x] `grep '.first!'` Widget — 无残留
- [x] `grep 'print('` CLIPulseBarApp — 无残留
- [x] `grep 'clipulse://auth/callback'` Android — 仅 Manifest fallback, SupabaseClient 已改 HTTPS
- [x] `grep 'Pair<String.*oauth'` — 无残留, 已全部改为 Triple
- [x] `grep 'fallbackToDestructiveMigration(true)'` — 仅 DEBUG 路径
- [x] Codex 交叉审查通过 — 确认所有修复正确
- [x] Google Sign-In 未受影响 (使用 Credential Manager, 不走 PKCE deep link)
- [x] assetlinks.json SHA256 指纹来源: keytool → cli-pulse-upload.jks

---

## 遗留待办 (下次修复)

| 优先级 | 项目 | 说明 |
|--------|------|------|
| P2 | UI 字符串本地化 | TeamView.swift, Android OverviewScreen/ProvidersScreen 等 |
| P2 | Android 邀请/角色 UI 对齐 iOS | TeamView.swift:222 有而 Android 没有 |
| P2 | Android 导出 UI | ExportUtil.kt 已有, 但无 Screen 暴露 |
| P3 | @unchecked Sendable 清理 | 有保护但不够优雅, 可用 actor 替代 |

---

*审查: Claude Opus 4.6 (主导) + Codex GPT (交叉验证, 11 项逐条确认)*
