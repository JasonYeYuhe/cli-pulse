# Privacy Policy

**CLI Pulse**  
**Last Updated: April 2, 2026**

## Overview

CLI Pulse is a developer tool for monitoring usage, quotas, and activity across
supported AI coding and CLI providers such as Codex, Claude, Gemini, and other
integrations added over time.

This Privacy Policy explains what information we collect, how we use it, where
it is stored, and what choices you have.

## Information We Collect

### Account Information

- Email address
- Authentication identifiers required to sign you in
- Account profile information returned by the authentication provider

Depending on the sign-in method you use, authentication may be handled through
email sign-in, password sign-in, one-time code verification, or Sign in with
Apple.

### Device and Sync Information

- Device name, device type, and platform
- Helper registration metadata
- Pairing and cloud sync state
- Last-seen timestamps and helper version

### Usage and App Data

- Provider usage summaries, quota percentages, reset times, and related
  metadata
- Session summaries and alert state
- App settings and provider enablement preferences
- Subscription status and entitlement information

### Local Provider Detection Data

On a Mac, the helper may inspect local process state, CLI configuration,
browser cookies, Keychain items, or other locally available provider session
artifacts in order to detect supported provider usage and quota information.

This local inspection happens on your device. CLI Pulse is designed to sync the
resulting usage metadata, not raw secrets such as passwords, browser cookies,
API keys, or refresh tokens.

## How We Use Your Information

We use collected information to:

- Authenticate your account
- Display usage, quota, cost, and alert information inside the app
- Sync data across your devices when Cloud Sync is enabled
- Register and manage helper-connected devices
- Restore subscription entitlements
- Improve reliability, debugging, and product support

## Data Storage

CLI Pulse uses a combination of local device storage and hosted backend
services.

- Some data is stored locally on your device, including helper state and local
  snapshots used for provider fallback behavior
- Cloud-synced account, device, session, provider, and settings data may be
  stored in backend infrastructure operated for CLI Pulse
- Authentication and database services may be provided through Supabase

## Data Retention

- Local snapshots and helper state remain on your device until removed,
  overwritten, or unpaired
- Cloud-synced data may be retained as needed to provide account history,
  dashboards, alerts, and subscription functionality
- Retention behavior may change as product tiers and sync features evolve

## Data Sharing

We do not sell your personal information.

We may share data only with the service providers necessary to operate CLI
Pulse, such as authentication, database, hosting, analytics, notification, and
subscription infrastructure providers.

## Third-Party Services

CLI Pulse may rely on third-party services including:

- **Supabase** for authentication and backend data services
- **Apple** for Sign in with Apple and in-app subscription billing through
  StoreKit
- **GitHub Pages** or similar static hosting for public product pages and legal
  documents

Supported provider usage data may be derived from local sessions or APIs
associated with third-party products such as Anthropic, OpenAI, Google, or
other provider services you use. CLI Pulse does not claim ownership over those
services or their policies.

## Your Choices and Rights

You can:

- View data associated with your account inside the app
- Sign out of the app
- Disconnect or unpair helper-connected devices
- Disable notifications at the operating system level
- Request account deletion from within the app where supported

## Children's Privacy

CLI Pulse is not intended for children under 13, and we do not knowingly
collect personal information from children.

## Changes to This Policy

We may update this Privacy Policy from time to time. When we do, we will update
the revision date on this page.

## Contact

If you have questions about this Privacy Policy, contact:

- `clipulse.support@gmail.com`
- [https://github.com/JasonYeYuhe/cli-pulse/issues](https://github.com/JasonYeYuhe/cli-pulse/issues)
