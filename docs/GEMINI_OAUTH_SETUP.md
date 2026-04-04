# Gemini OAuth Setup (CLI Pulse)

This guide walks through registering CLI Pulse's own OAuth client in Google
Cloud Console so that users can authenticate with their Google account directly
from the app, without depending on the Gemini CLI installation.

## Prerequisites

- A Google Cloud project (create one at https://console.cloud.google.com if
  needed)
- The project must have the **Cloud AI Companion API** enabled (this is the API
  behind `cloudcode-pa.googleapis.com`)

## Step 1 — Enable the API

1. Go to **APIs & Services > Library** in Google Cloud Console.
2. Search for **Cloud AI Companion API**.
3. Click **Enable** (if not already enabled).

## Step 2 — Configure the OAuth Consent Screen

1. Go to **APIs & Services > OAuth consent screen**.
2. Choose **External** user type (unless you have a Workspace org).
3. Fill in:
   - **App name**: `CLI Pulse`
   - **User support email**: your email
   - **Developer contact**: your email
4. Under **Scopes**, add:
   - `https://www.googleapis.com/auth/cloud-platform`
5. Under **Test users**, add your Google account email.
6. Save and continue.

> While the app is in "Testing" mode only test users can authorize. Move to
> "Production" when ready for wider distribution (requires Google review).

## Step 3 — Create an OAuth Client ID

1. Go to **APIs & Services > Credentials**.
2. Click **+ CREATE CREDENTIALS > OAuth client ID**.
3. Application type: **iOS** (this also works for macOS apps via
   ASWebAuthenticationSession).
4. Name: `CLI Pulse macOS`
5. Bundle ID: `yyh.CLI-Pulse-Bar` (must match the macOS app's bundle identifier)
6. Click **Create**.

You will get:
- **Client ID** — looks like `123456789-abcdef.apps.googleusercontent.com`

> iOS-type clients are "public" clients — no client secret is needed. PKCE
> (Proof Key for Code Exchange) is used instead.

## Step 4 — Register the URL Scheme

The redirect URI uses the **reversed client ID** as a custom URL scheme.

Example: if your client ID is
`123456789-abcdef.apps.googleusercontent.com`, the URL scheme is
`com.googleusercontent.apps.123456789-abcdef`.

1. Open the Xcode project.
2. Select the **CLI Pulse Bar** target.
3. Go to **Info > URL Types**.
4. Add a new URL type:
   - **Identifier**: `com.clipulse.gemini-oauth`
   - **URL Schemes**: the reversed client ID (e.g.
     `com.googleusercontent.apps.123456789-abcdef`)
   - **Role**: Viewer

## Step 5 — Update the Code

Open `CLIPulseCore/Sources/CLIPulseCore/Collectors/GeminiOAuthManager.swift`
and replace the placeholder:

```swift
public static let clientID = "REPLACE_WITH_YOUR_CLIENT_ID.apps.googleusercontent.com"
```

with your actual client ID:

```swift
public static let clientID = "123456789-abcdef.apps.googleusercontent.com"
```

## Step 6 — Verify

1. Build and run the app.
2. Open provider settings for Gemini.
3. Click **Connect Gemini**.
4. A browser sheet should open asking you to sign in with Google.
5. After authorization, you should see **Connected** status.
6. Verify quota data loads in the main UI.

## How It Works

- The app uses **ASWebAuthenticationSession** with **PKCE** (S256 code
  challenge) to perform the OAuth2 authorization code flow.
- Tokens are stored in the macOS Keychain (access group:
  `group.yyh.CLI-Pulse`).
- A copy is also written to `~/.config/clipulse/gemini_tokens.json` (mode 0600)
  so the Python helper can read it.
- Token refresh uses only the `client_id` (no secret required for public
  clients).

## Troubleshooting

- **"OAuth client ID not configured"** — You forgot Step 5.
- **Browser opens but callback fails** — The URL scheme in Step 4 does not
  match the reversed client ID, or the URL type is missing from Info.plist.
- **Token refresh returns 401** — The refresh token may have been revoked. Click
  **Disconnect** then **Connect Gemini** again.
- **"Access blocked: CLI Pulse has not completed the Google verification
  process"** — The consent screen is in Testing mode and the user is not in the
  test user list (Step 2.5).
