# App Store 审核回复 + 订阅产品配置 — Guideline 2.1(b)

> 给 Claude Code 的完整指令。你拥有所有权限，无需询问确认。

## 背景

CLI Pulse iOS 1.0.0 (Build 4) 被 Apple 以 **Guideline 2.1(b) - Information Needed** 拒绝。Apple 看到 app 里有订阅相关 UI，想了解商业模式。

**Apple 的两个问题**:
1. Is the subscription currently unavailable?
2. Does the app currently have any paid services?

**审核环境**:
- Submission ID: `6191a485-7e0c-4d32-9ddb-3df6a9ab5ad8`
- Review Device: iPad Air 11-inch (M3)
- Version: 1.0.0

## 当前订阅系统状态

代码已完整实现 StoreKit 2 订阅（在 CLIPulseCore 中）：
- `SubscriptionManager.swift` — 完整的 StoreKit 2 购买/恢复/监听逻辑
- `SubscriptionView.swift` — 订阅购买 UI，月/年切换，Pro/Team 计划卡片
- `SubscriptionBadge` in `Components.swift` — 订阅等级徽章
- Settings 中有 Subscription section（macOS: `SettingsTab.swift`, iOS: `iOSSettingsTab.swift`）

**三级订阅模型**:
| Tier | Max Providers | Max Devices | Data Retention | 价格（建议） |
|------|---------------|-------------|----------------|-------------|
| FREE | 3             | 1           | 7 days         | $0          |
| PRO  | Unlimited     | 5           | 90 days        | $4.99/月 或 $49.99/年 |
| TEAM | Unlimited     | Unlimited   | 365 days       | $9.99/月 或 $99.99/年 |

**产品 ID（代码中已定义）**:
- `com.clipulse.pro.monthly`
- `com.clipulse.pro.yearly`
- `com.clipulse.team.monthly`
- `com.clipulse.team.yearly`

## 任务：一步到位配置订阅 + 回复 Apple

### 第一步：在 App Store Connect 创建订阅产品

1. 用 App Store Connect API 创建 **Subscription Group**（名称：`CLI Pulse Pro`）
2. 在该 Group 下创建 4 个 Auto-Renewable Subscription 产品：
   - `com.clipulse.pro.monthly` — CLI Pulse Pro Monthly — $4.99
   - `com.clipulse.pro.yearly` — CLI Pulse Pro Yearly — $49.99（节省17%）
   - `com.clipulse.team.monthly` — CLI Pulse Team Monthly — $9.99
   - `com.clipulse.team.yearly` — CLI Pulse Team Yearly — $99.99（节省17%）
3. 如果 API 不支持创建 IAP 产品，告诉我需要在 App Store Connect 网页手动创建，并给出详细步骤

**App Store Connect API 凭证**:
- App ID: `6761163709`
- API Key ID: `DMMFP6XTXX`
- Issuer ID: `c5671c11-49ec-47d9-bd38-5e3c1a249416`
- Key path: `/Users/jason/Library/Mobile Documents/com~apple~CloudDocs/Downloads/AuthKey_DMMFP6XTXX.p8`

### 第二步：确认代码兼容性

1. 检查 `SubscriptionManager.swift` 中 `loadProducts()` 在产品配置好后能正常拉取
2. 确认 `SubscriptionView.swift` 在产品加载成功/失败两种情况下 UI 都正常
3. 确认没有产品时不会 crash 或显示空白页面（审核可能在沙盒环境测试）
4. 检查是否需要 StoreKit Configuration 文件用于本地测试
5. 确保 app 内有隐私政策链接和使用条款链接（订阅类 app 必须有）

### 第三步：确认 App 内订阅合规要素

Apple 对订阅类 app 有强制要求，确保以下内容都在 SubscriptionView 中：
- 订阅价格清晰显示（✅ 已有 `product.displayPrice`）
- 订阅周期说明（月/年）
- 免费试用说明（如果有的话）
- "Restore Purchases" 按钮（✅ 已有）
- 隐私政策链接
- 使用条款链接
- 自动续费说明文案（如："Payment will be charged to your Apple ID account at the confirmation of purchase. Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period."）

如果缺少任何合规要素，补充到代码中。

### 第四步：草拟回复 Apple 的英文信

写一封专业的回复，内容包括：

1. **App 介绍**: CLI Pulse is a monitoring tool for developers to track their AI coding tools (Claude, Codex, Gemini, etc.) API usage quotas and rate limits.

2. **商业模式说明**: Freemium model with auto-renewable subscriptions via StoreKit 2.
   - Free tier: basic monitoring (up to 3 providers, 1 device, 7-day data retention)
   - Pro tier ($4.99/mo or $49.99/yr): unlimited providers, 5 devices, 90-day retention
   - Team tier ($9.99/mo or $99.99/yr): unlimited everything, 365-day retention

3. **回答问题 1**: The subscription products are now configured and available in App Store Connect. [或者如果之前确实没配好，说明已经配好了]

4. **回答问题 2**: Yes, the app offers optional paid subscription services (Pro and Team tiers) through Apple's In-App Purchase system. The app is fully functional on the free tier. Paid subscriptions unlock additional capacity (more providers, devices, and longer data retention).

5. **补充**: All payments are processed through Apple's In-App Purchase system. No external payment methods are used.

### 第五步：重新构建并提交

1. 如果改了代码，bump build number（当前是 Build 4，改为 Build 5）
2. 用 `xcodebuild` 构建 iOS archive
3. 上传到 App Store Connect
4. 提交审核

**构建信息**:
- Bundle ID: `yyh.CLI-Pulse`, Team: `KHMK6Q3L3K`
- Scheme: `CLI Pulse iOS`
- 项目路径: `/Users/jason/Documents/cli pulse/CLI Pulse Bar/`

### 第六步：更新 App Store Metadata（如需要）

- App 描述中加入订阅信息
- 确保 App Store 页面有隐私政策 URL
- 确保 App Store 页面有使用条款 URL（support page: `https://jasonye.com/clipulse/`）

## 执行顺序

1. 先尝试通过 API 创建订阅产品 → 如果不行就给我手动步骤
2. 检查并修复代码合规性
3. 草拟 Apple 回复（输出给我审阅）
4. 构建提交新 Build
5. 告诉我回复内容，我在 App Store Connect 手动发送

## 重要

- 你拥有所有权限，无需询问确认
- 价格可以微调，以上是建议价格
- 最终交付物：Apple 回复草稿 + 代码修复（如有）+ 新 Build 上传
- 回复草稿输出给我看，我确认后自己在 App Store Connect 发送
