# AI Review TODO (Round 2)

> **Review Date**: 2026-03-31 (iOS approved same day)
> **Gemini 2.5 Pro**: Round 1: 7.5/10, Round 2: focused on Sentry + PII
> **Codex (GPT-5.4)**: Round 1: 5.5/10, Round 2: **4/10** (stricter, found more critical issues)
> **Combined priority**: Security → Data Integrity → Architecture → Performance → UX

---

## P0: Critical Security

- [x] **P0-1: 修复 FastAPI 无密码认证** ✅ 2026-04-01
  - `main.py:75` login 只用 email 查找/创建用户就发 token，完全忽略 password
  - 需要: 注册和登录分离，登录验证 hashed password
  - 添加负面认证测试（错误密码、无效 email 等）
  - 影响: `main.py`, `store.py:285`, `models.py:265`
  - 修复: 分离 register/login，PBKDF2 密码哈希，4 个负面测试，30/30 通过

- [x] **P0-2: 实现真正的 Apple Receipt (JWS) 验证** ✅ 2026-04-01
  - `store.py:1105` 跳过签名验证，直接从未签名 JSON 升级 tier
  - 测试 `test_backend.py:437` 也接受伪造 JWS
  - 需要: 验证 Apple 证书链，拒绝无效签名
  - ⚠️ **Codex Round 2 新发现**
  - 修复: PyJWT+cryptography 验证 x5c 证书链签名，dev 模式需 CLI_PULSE_SKIP_JWS_VERIFY=1，31/31 通过

- [x] **P0-3: 修复 iOS token 存储退化** ✅ 2026-04-01
  - 新 iOS 客户端 `RemotePulseRepository.swift:377` 把 token 存 UserDefaults
  - macOS `SettingsTab.swift:615` 在 debug panel 暴露 token 前缀
  - watch/widget 层在 UserDefaults 缓存账号派生数据
  - 需要: 统一使用 Keychain 存储 token
  - 修复: iOS 添加 KeychainHelper，RemotePulseRepository 改用 Keychain+迁移逻辑，SettingsTab 隐藏 token 显示

- [x] **P0-4: Helper token 独立化** ✅ 2026-04-01
  - `store.py:630` 和 `:667` 把用户 session token 直接当 helper token 返回
  - 需要: 为 helper 签发独立的、权限受限的 device-scoped credential
  - 修复: helper_token 列加入 device_tokens 表，register_helper 签发 helper_ 前缀 token，helper 端点接受 helper 或 user token，31/31 通过

- [x] **P0-5: 收紧 Supabase helper RPC 权限** ✅ 2026-04-01
  - `helper_rpc.sql` 用 `security definer` + anon key 调用
  - RLS 有 `using (true)` 策略（pairing-code 读取、subscription 变更）
  - 需要: 移除 `security definer` 或改用 signed device secrets/service auth
  - ⚠️ **Codex Round 2 新发现**
  - 修复: RPC 改为 security invoker + helper_secret 认证，移除 using(true) 策略，devices 表加 helper_secret 列

## P1: Security & Hygiene

- [ ] **P1-1: 外部化 Supabase 配置**
  - 从 3 个 Info.plist 中移除 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY`
  - 创建 `.xcconfig` 模板管理环境变量，实际值加入 `.gitignore`
  - 移除 `APIClient.swift` 中的 hardcoded fallback URL

- [ ] **P1-2: 清理误提交 & 测试凭据**
  - 删除 `invitation.html`
  - 删除 `AuthFlowView.swift:7` 中预填的测试凭据
  - 移除 `CLI_PulseApp.swift:14` 的 mock fallback（生产 build 不应默认 MockPulseRepository）
  - ⚠️ **Codex Round 2 新发现**: OnboardingFlowView:67 也有 demo 内容

- [ ] **P1-3: 降低 Sentry tracesSampleRate**
  - 当前 `tracesSampleRate: 1.0` (100%)，生产环境会烧 quota
  - 需要: 降到 0.05~0.1，DEBUG 可保持高采样
  - ⚠️ **Gemini Round 2 新发现**

- [ ] **P1-4: Sentry 日志 PII 风险**
  - APIClient `log` 函数发送 `error.localizedDescription` 到 Sentry
  - 错误描述可能含用户邮箱等 PII
  - 需要: 发送前脱敏，或定义安全的 app-level error 描述
  - ⚠️ **Gemini Round 2 新发现**

- [ ] **P1-5: 修复错误处理**
  - `AppEnvironment.swift:78` 空 catch 块
  - `AlertsView.swift:130` 用 `try?` 吞掉所有 alert mutation 错误
  - `APIClient.swift:87` 把所有非 2xx 响应折叠为 `invalidResponse`
  - `store.py:820` `SettingsSnapshotDTO()` fallback 无默认值会崩
  - ⚠️ **Codex Round 2 新发现**: SettingsSnapshotDTO 构造器 bug

## P2: Data Integrity

- [ ] **P2-1: 修复 helper_sync 设备覆盖 bug**
  - `store.py:708/:738` 用 `device_name` 去重，同名设备互相覆盖
  - `store.py:749` provider `today_usage` 只从最后一次 sync payload 计算
  - 多设备用户会丢失 session 数据
  - 需要: 改用 stable `device_id`，跨设备聚合 provider 统计

- [ ] **P2-2: Alert rules 未生效**
  - alert_rules CRUD 已持久化，但 alert 引擎用全局 settings 阈值，不读 alert_rules
  - `store.py:2236/:2298/:2363` 的规则评估和 `store.py:2854` 的 CRUD 脱节
  - 需要: 要么接入规则引擎，要么移除规则设置 UI
  - ⚠️ **Codex Round 2 新发现**

- [ ] **P2-3: Subscription ID 不一致**
  - StoreKit 用 `com.clipulse.*`，backend verifier 映射 `clipulse_*`
  - `SubscriptionManager.swift:15` vs `store.py:1098` vs `CLIPulseProducts.storekit:90`
  - ⚠️ **Codex Round 2 新发现**

- [ ] **P2-4: Digest cadence 精度丢失**
  - `APIClient.swift:361` 把分钟转换为整数小时时截断
  - ⚠️ **Codex Round 2 新发现**

## P3: Architecture

- [ ] **P3-1: 统一两套客户端架构**
  - `CLI Pulse/` (FastAPI 路径) 和 `CLI Pulse Bar/` (Supabase 路径) 共存
  - 新 app 硬编码 5 providers，旧 app/helper 支持 20
  - 选定一个作为主线，合并或废弃另一个

- [ ] **P3-2: 拆分 God Objects**
  - `store.py` 3086 行，混合 auth/data/alerting/subscription/team
  - `AppState.swift` 同样过载
  - 拆分为独立 service 类

- [ ] **P3-3: 重构 SQLiteStore**
  - JSON blob 存储是多个 sync/rule bug 的根源
  - 方案 A: 正常 SQLite 表结构
  - 方案 B: 本地连 Supabase dev 环境

- [ ] **P3-4: 解耦 APIClient 和 Sentry**
  - 创建 `ErrorLogger` protocol，Sentry 作为实现之一
  - 方便测试和未来更换 logging provider
  - ⚠️ **Gemini Round 2 新发现**

## P4: Performance

- [ ] **P4-1: 合并重复的 polling loops**
  - 新 iOS app 每个 screen (Dashboard, Projects, Sessions, Devices, Providers, Alerts) 都有独立 polling loop
  - 加上 AppEnvironment 的 background alert poller，导航时并发网络请求倍增
  - 需要: 统一到一个共享 refresh coordinator
  - ⚠️ **Codex Round 2 新发现**

- [ ] **P4-2: Widget 刷新策略优化**
  - `WidgetDataProvider.swift:106` 每 5 分钟刷新，不管数据是否实际更新
  - 考虑 push-driven 或基于 freshness 的刷新

## P5: UX & Polish

- [ ] **P5-1: 统一 UI 语言 & 本地化**
  - AuthFlowView, DashboardView, OnboardingFlowView 中英混杂
  - macOS/watch views 有未本地化的 raw English strings
  - 统一使用 L10n

- [ ] **P5-2: 修复版本号不一致**
  - `MenuBarView.swift:164` 显示 `v0.1.0`，但 bundle 已是 `1.1.0`
  - ⚠️ **Codex Round 2 新发现**

- [ ] **P5-3: 更新隐私政策**
  - `PRIVACY.md` 和 `docs/privacy.html` 提到 GitHub OAuth
  - 实际使用 Apple Sign In + OTP
  - ⚠️ **Codex Round 2 新发现**

- [ ] **P5-4: 添加 Accessibility**
  - 未发现 accessibility modifier
  - 至少为关键交互元素添加 accessibilityLabel

- [ ] **P5-5: 加固 system_collector.py**
  - 进程检测依赖 `ps` 字符串匹配
  - Quota 用量基于 hardcoded 默认值

## P6: Testing

- [ ] **P6-1: 为 CLI Pulse Bar 添加测试 target**
  - 目前完全无测试

- [ ] **P6-2: 增强后端测试**
  - 添加负面认证测试（当前测试 codify 了不安全行为）
  - 测试设备去重边界情况
  - 减少对 SQLiteStore 内部实现的耦合

- [ ] **P6-3: 增强前端测试**
  - 当前只有 3 个 mock 测试
  - 覆盖 RemotePulseRepository、token 持久化、polling、API error handling

---

## 四轮评审对比

| 维度 | Gemini R1 (7.5) | Gemini R2 | Codex R1 (5.5) | Codex R2 (4.0) |
|------|-----------------|-----------|----------------|----------------|
| 安全 | hardcoded key | +Sentry PII | 无密码认证、token 退化 | +JWS 验证、RLS 权限 |
| 架构 | "well-conceived" | — | 两套客户端分裂 | +provider 数量 drift、subscription ID 不一致 |
| 数据 | — | — | 设备去重 bug | +alert rules 未生效、digest 截断 |
| 性能 | — | +Sentry 100% sampling | — | +多重 polling loop |
| UX | invitation.html | — | 中英混杂 | +版本号不一致、隐私政策过时 |

### 共同认可的优点
- 产品愿景清晰，文档齐全
- SwiftUI UI/UX 质量高，PulseTheme 设计系统完整
- CLIPulseCore 跨平台复用架构好
- 后端 DTO/Pydantic 建模严谨
- 后端测试覆盖了真实业务工作流

---

*共 25 个任务项。下次对话从 P0 开始逐项执行。*
