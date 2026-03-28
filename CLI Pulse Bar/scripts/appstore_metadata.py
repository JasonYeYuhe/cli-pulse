#!/usr/bin/env python3
"""
CLI Pulse - App Store Connect Metadata & Screenshot Uploader
Uses App Store Connect API v1
"""

import jwt
import time
import requests
import json
import hashlib
import os
import sys

# --- Config ---
API_KEY_ID = "DMMFP6XTXX"
API_ISSUER = "c5671c11-49ec-47d9-bd38-5e3c1a249416"
API_KEY_PATH = os.path.expanduser(
    "~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/AuthKey_DMMFP6XTXX.p8"
)
APP_ID = "6761163709"
BASE_URL = "https://api.appstoreconnect.apple.com/v1"

# --- JWT Token ---
def generate_token():
    with open(API_KEY_PATH, "r") as f:
        private_key = f.read()
    now = int(time.time())
    payload = {
        "iss": API_ISSUER,
        "iat": now,
        "exp": now + 1200,  # 20 min
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": API_KEY_ID})

def headers():
    return {
        "Authorization": f"Bearer {generate_token()}",
        "Content-Type": "application/json",
    }

def api_get(path):
    r = requests.get(f"{BASE_URL}{path}", headers=headers())
    r.raise_for_status()
    return r.json()

def api_post(path, data, raise_on_error=True):
    r = requests.post(f"{BASE_URL}{path}", headers=headers(), json=data)
    if r.status_code >= 400:
        print(f"  POST {path} -> {r.status_code}")
        try:
            errors = r.json().get("errors", [])
            for e in errors:
                print(f"    {e.get('detail', e.get('title', 'Unknown error'))}")
        except Exception:
            print(f"  {r.text[:300]}")
        if raise_on_error:
            r.raise_for_status()
        return None
    return r.json()

def api_patch(path, data, raise_on_error=True):
    r = requests.patch(f"{BASE_URL}{path}", headers=headers(), json=data)
    if r.status_code >= 400:
        try:
            errors = r.json().get("errors", [])
            for e in errors:
                print(f"    {e.get('detail', e.get('title', 'Unknown error'))}")
        except Exception:
            print(f"  {r.text[:300]}")
        if raise_on_error:
            r.raise_for_status()
        return None
    return r.json()

def api_delete(path):
    r = requests.delete(f"{BASE_URL}{path}", headers=headers())
    return r.status_code


# ============================================================
# 1. Get or create App Store Version
# ============================================================
def get_or_create_version(platform, version="1.0.0"):
    print(f"\n{'='*50}")
    print(f"  Setting up {platform} v{version}")
    print(f"{'='*50}")

    # Check existing versions
    r = api_get(f"/apps/{APP_ID}/appStoreVersions?filter[platform]={platform}")
    versions = r.get("data", [])

    for v in versions:
        if v["attributes"]["versionString"] == version:
            print(f"  Found existing version: {v['id']}")
            return v["id"]

    # Create new version
    print(f"  Creating new version {version} for {platform}...")
    data = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": platform,
                "versionString": version,
            },
            "relationships": {
                "app": {
                    "data": {"type": "apps", "id": APP_ID}
                }
            },
        }
    }
    r = api_post("/appStoreVersions", data)
    version_id = r["data"]["id"]
    print(f"  Created version: {version_id}")
    return version_id


# ============================================================
# 2. Set Localization (description, keywords, etc.)
# ============================================================
def set_localization(version_id, locale="en-US"):
    print(f"\n  Setting {locale} localization...")

    description = """CLI Pulse monitors your AI coding tool usage across Claude, Codex, Gemini, OpenRouter, Ollama, and 20+ providers in real-time.

FEATURES:
- Real-time usage monitoring for all major AI coding assistants
- Track API costs and spending across providers
- Session history with detailed metrics
- Smart alerts for rate limits, errors, and unusual activity
- Provider-level analytics with usage breakdowns

MULTI-PLATFORM:
- macOS menu bar app for quick access
- iPhone & iPad app with adaptive layouts
- Apple Watch app with quick glance dashboard
- Home Screen & Lock Screen widgets

PRIVACY-FIRST:
- All data stays on your local network
- No cloud sync or third-party analytics
- Connects to your self-hosted CLI Pulse backend

Perfect for developers who use multiple AI coding tools and want to understand their usage patterns, control costs, and stay informed about their AI assistant activity."""

    keywords = "AI,coding,monitor,Claude,Codex,Gemini,developer,usage,API,tools"

    whats_new = "Initial release with support for macOS, iOS, iPadOS, watchOS, and widgets."

    promo = "Monitor all your AI coding tools in one place"

    support_url = "https://github.com/jasonyeyuhe/cli-pulse"

    # Get existing localizations
    r = api_get(f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    localizations = r.get("data", [])

    loc_id = None
    for loc in localizations:
        if loc["attributes"]["locale"] == locale:
            loc_id = loc["id"]
            break

    loc_data = {
        "description": description,
        "keywords": keywords,
        "promotionalText": promo,
        "supportUrl": support_url,
    }

    if loc_id:
        print(f"  Updating existing localization {loc_id}...")
        result = api_patch(f"/appStoreVersionLocalizations/{loc_id}", {
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": loc_id,
                "attributes": loc_data,
            }
        }, raise_on_error=False)
        if result is None:
            print(f"  (localization update skipped due to version state)")
        # whatsNew only for updates, not first version - try separately
        api_patch(f"/appStoreVersionLocalizations/{loc_id}", {
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": loc_id,
                "attributes": {"whatsNew": whats_new},
            }
        }, raise_on_error=False)
    else:
        print(f"  Creating new localization...")
        loc_data["locale"] = locale
        r = api_post("/appStoreVersionLocalizations", {
            "data": {
                "type": "appStoreVersionLocalizations",
                "attributes": loc_data,
                "relationships": {
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": version_id}
                    }
                },
            }
        })
        loc_id = r["data"]["id"]

    print(f"  Localization set: {loc_id}")
    return loc_id


# ============================================================
# 3. Upload Screenshots
# ============================================================
def upload_screenshots(loc_id, screenshot_files, display_type):
    """
    display_type examples:
      APP_IPHONE_67: iPhone 6.7"
      APP_IPAD_PRO_129: iPad Pro 12.9"
      APP_DESKTOP: macOS
      APP_WATCH_ULTRA: Apple Watch Ultra
      APP_WATCH_SERIES_10: Watch Series 10
    """
    print(f"\n  Uploading {len(screenshot_files)} screenshots ({display_type})...")

    # Get existing screenshot sets
    r = api_get(f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    sets = r.get("data", [])

    set_id = None
    for s in sets:
        if s["attributes"]["screenshotDisplayType"] == display_type:
            set_id = s["id"]
            break

    if not set_id:
        # Create screenshot set
        r = api_post("/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {
                    "screenshotDisplayType": display_type,
                },
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                    }
                },
            }
        }, raise_on_error=False)
        if r is None:
            print(f"  Cannot create screenshot set (version state). Skipping.")
            return
        set_id = r["data"]["id"]
        print(f"  Created screenshot set: {set_id}")
    else:
        # Check if we can modify - try deleting existing screenshots
        r = api_get(f"/appScreenshotSets/{set_id}/appScreenshots")
        existing = r.get("data", [])
        if existing:
            result = api_delete(f"/appScreenshots/{existing[0]['id']}")
            if result >= 400:
                print(f"  Cannot modify screenshots (version state). Skipping.")
                return
            for ss in existing[1:]:
                api_delete(f"/appScreenshots/{ss['id']}")
        print(f"  Using screenshot set: {set_id}")

    # Upload each screenshot
    for i, filepath in enumerate(screenshot_files):
        filename = os.path.basename(filepath)
        filesize = os.path.getsize(filepath)

        with open(filepath, "rb") as f:
            file_data = f.read()
        checksum = hashlib.md5(file_data).hexdigest()

        print(f"  [{i+1}/{len(screenshot_files)}] Reserving {filename} ({filesize} bytes)...")

        # Reserve upload
        r = api_post("/appScreenshots", {
            "data": {
                "type": "appScreenshots",
                "attributes": {
                    "fileName": filename,
                    "fileSize": filesize,
                },
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": set_id}
                    }
                },
            }
        }, raise_on_error=False)

        if r is None:
            print(f"    Failed to reserve. Skipping remaining screenshots.")
            return

        screenshot_id = r["data"]["id"]
        upload_ops = r["data"]["attributes"].get("uploadOperations", [])

        if not upload_ops:
            print(f"    No upload operations returned, skipping...")
            continue

        # Upload parts
        for op in upload_ops:
            url = op["url"]
            op_headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
            offset = op["offset"]
            length = op["length"]
            chunk = file_data[offset:offset + length]

            resp = requests.put(url, headers=op_headers, data=chunk)
            if resp.status_code >= 400:
                print(f"    Upload chunk failed: {resp.status_code} {resp.text[:200]}")

        # Commit
        api_patch(f"/appScreenshots/{screenshot_id}", {
            "data": {
                "type": "appScreenshots",
                "id": screenshot_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": checksum,
                },
            }
        })
        print(f"    Uploaded: {filename}")

    print(f"  All {display_type} screenshots uploaded.")


# ============================================================
# 4. Set App Info (category, etc.)
# ============================================================
def set_app_info():
    print(f"\n  Setting app info (category)...")
    r = api_get(f"/apps/{APP_ID}/appInfos")
    infos = r.get("data", [])
    if not infos:
        print("  No app info found!")
        return

    info_id = infos[0]["id"]

    # Set primary category to Developer Tools
    try:
        api_patch(f"/appInfos/{info_id}", {
            "data": {
                "type": "appInfos",
                "id": info_id,
                "relationships": {
                    "primaryCategory": {
                        "data": {"type": "appCategories", "id": "DEVELOPER_TOOLS"}
                    },
                },
            }
        })
        print(f"  Category set to Developer Tools")
    except Exception as e:
        print(f"  Category update note: {e}")

    # Set app info localization
    r = api_get(f"/appInfos/{info_id}/appInfoLocalizations")
    locs = r.get("data", [])
    for loc in locs:
        if loc["attributes"]["locale"] == "en-US":
            api_patch(f"/appInfoLocalizations/{loc['id']}", {
                "data": {
                    "type": "appInfoLocalizations",
                    "id": loc["id"],
                    "attributes": {
                        "name": "CLI Pulse",
                        "privacyPolicyUrl": "https://github.com/jasonyeyuhe/cli-pulse/blob/main/PRIVACY.md",
                    }
                }
            })
            print(f"  App info localization updated")
            break


# ============================================================
# Main
# ============================================================
def main():
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_DIR = os.path.dirname(SCRIPT_DIR)

    print("=" * 50)
    print("  CLI Pulse - App Store Connect Metadata Setup")
    print("=" * 50)

    # Test API connection
    print("\n  Testing API connection...")
    r = api_get(f"/apps/{APP_ID}")
    app_name = r["data"]["attributes"]["name"]
    print(f"  Connected! App: {app_name}")

    # Set app info
    set_app_info()

    # --- macOS ---
    mac_version_id = get_or_create_version("MAC_OS")
    mac_loc_id = set_localization(mac_version_id)

    mac_screenshots = sorted([
        os.path.join(os.path.expanduser("~/Desktop/CLIPulseBar-Screenshots"), f)
        for f in os.listdir(os.path.expanduser("~/Desktop/CLIPulseBar-Screenshots"))
        if f.endswith("_2880x1800.png")
    ])
    if mac_screenshots:
        upload_screenshots(mac_loc_id, mac_screenshots, "APP_DESKTOP")

    # --- iOS ---
    ios_version_id = get_or_create_version("IOS")
    ios_loc_id = set_localization(ios_version_id)

    # iPhone 6.7" screenshots
    ios_dir = os.path.join(PROJECT_DIR, "build/ios-screenshots")
    if os.path.isdir(ios_dir):
        iphone_screenshots = sorted([
            os.path.join(ios_dir, f)
            for f in os.listdir(ios_dir)
            if f.endswith(".png")
        ])
        if iphone_screenshots:
            upload_screenshots(ios_loc_id, iphone_screenshots, "APP_IPHONE_67")

    # iPad Pro 12.9" screenshots
    ipad_dir = os.path.join(PROJECT_DIR, "build/ipad-screenshots")
    if os.path.isdir(ipad_dir):
        ipad_screenshots = sorted([
            os.path.join(ipad_dir, f)
            for f in os.listdir(ipad_dir)
            if f.endswith(".png")
        ])
        if ipad_screenshots:
            upload_screenshots(ios_loc_id, ipad_screenshots, "APP_IPAD_PRO_3GEN_129")

    print("\n" + "=" * 50)
    print("  Metadata setup complete!")
    print("=" * 50)
    print("\n  Next steps:")
    print("  1. Go to App Store Connect to review")
    print("  2. Add privacy information if needed")
    print("  3. Submit for review")
    print()


if __name__ == "__main__":
    main()
