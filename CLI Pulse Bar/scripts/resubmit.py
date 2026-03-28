#!/usr/bin/env python3
"""
CLI Pulse - Cancel review, update screenshots, select new build, resubmit.
"""
import jwt, time, requests, os, hashlib, sys

API_KEY_ID = "DMMFP6XTXX"
API_ISSUER = "c5671c11-49ec-47d9-bd38-5e3c1a249416"
API_KEY_PATH = os.path.expanduser(
    "~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/AuthKey_DMMFP6XTXX.p8"
)
APP_ID = "6761163709"
BASE = "https://api.appstoreconnect.apple.com/v1"

with open(API_KEY_PATH) as f:
    _key = f.read()

def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": API_ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        _key, algorithm="ES256", headers={"kid": API_KEY_ID},
    )

def hdr():
    return {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}

def get(path):
    r = requests.get(f"{BASE}{path}", headers=hdr())
    r.raise_for_status()
    return r.json()

def post(path, data):
    r = requests.post(f"{BASE}{path}", headers=hdr(), json=data)
    if r.status_code >= 400:
        print(f"  POST {path} -> {r.status_code}")
        try:
            for e in r.json().get("errors", []):
                print(f"    {e.get('detail', e.get('title'))}")
        except:
            print(f"    {r.text[:300]}")
        return None
    return r.json()

def patch(path, data):
    r = requests.patch(f"{BASE}{path}", headers=hdr(), json=data)
    if r.status_code >= 400:
        print(f"  PATCH {path} -> {r.status_code}")
        try:
            for e in r.json().get("errors", []):
                print(f"    {e.get('detail', e.get('title'))}")
        except:
            print(f"    {r.text[:300]}")
        return None
    return r.json()

def delete(path):
    r = requests.delete(f"{BASE}{path}", headers=hdr())
    return r.status_code


# ── 1. Cancel existing review submissions ──
def cancel_reviews():
    print("\n[1] Canceling existing review submissions...")
    r = get(f"/apps/{APP_ID}/reviewSubmissions")
    for sub in r.get("data", []):
        state = sub["attributes"]["state"]
        sub_id = sub["id"]
        print(f"  Submission {sub_id} state={state}")
        if state in ("WAITING_FOR_REVIEW", "IN_REVIEW"):
            result = patch(f"/reviewSubmissions/{sub_id}", {
                "data": {"type": "reviewSubmissions", "id": sub_id,
                         "attributes": {"canceled": True}}
            })
            if result:
                print(f"  Canceled: {sub_id}")
            else:
                # Try legacy API
                print(f"  Trying legacy appStoreVersionSubmissions...")
                r2 = get(f"/appStoreVersionSubmissions")
                # Just proceed - may already be canceled


# ── 2. Select new build ──
def select_build(version_id, platform_label):
    print(f"\n[2] Selecting latest build for {platform_label}...")

    # Wait for build to be processed
    for attempt in range(12):
        r = get(f"/builds?filter[app]={APP_ID}&filter[version]=4&sort=-uploadedDate&limit=5")
        builds = r.get("data", [])
        for b in builds:
            proc = b["attributes"].get("processingState", "")
            ver = b["attributes"].get("version", "")
            print(f"  Build {b['id']}: version={ver} processing={proc}")
            if proc == "VALID" and ver == "4":
                # Select this build
                patch(f"/appStoreVersions/{version_id}", {
                    "data": {
                        "type": "appStoreVersions",
                        "id": version_id,
                        "relationships": {
                            "build": {
                                "data": {"type": "builds", "id": b["id"]}
                            }
                        }
                    }
                })
                print(f"  Selected build {b['id']}")
                return True

        if attempt < 11:
            print(f"  Waiting for build processing... ({attempt+1}/12)")
            time.sleep(30)

    print(f"  WARNING: Could not find valid build 3. Proceeding with existing build.")
    return False


# ── 3. Upload screenshots ──
def upload_screenshots(loc_id, files, display_type):
    print(f"\n  Uploading {len(files)} screenshots ({display_type})...")

    # Get or create screenshot set
    r = get(f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    set_id = None
    for s in r.get("data", []):
        if s["attributes"]["screenshotDisplayType"] == display_type:
            set_id = s["id"]
            break

    if set_id:
        # Delete existing screenshots
        r2 = get(f"/appScreenshotSets/{set_id}/appScreenshots")
        for ss in r2.get("data", []):
            delete(f"/appScreenshots/{ss['id']}")
            print(f"    Deleted old screenshot {ss['id']}")
    else:
        r = post("/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                    }
                }
            }
        })
        if not r:
            print(f"    Failed to create screenshot set")
            return
        set_id = r["data"]["id"]

    # Upload each file
    for i, filepath in enumerate(files):
        filename = os.path.basename(filepath)
        filesize = os.path.getsize(filepath)
        with open(filepath, "rb") as f:
            data = f.read()
        checksum = hashlib.md5(data).hexdigest()

        print(f"    [{i+1}/{len(files)}] {filename} ({filesize} bytes)...")

        r = post("/appScreenshots", {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": filename, "fileSize": filesize},
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": set_id}
                    }
                }
            }
        })
        if not r:
            print(f"    Failed to reserve upload")
            continue

        ss_id = r["data"]["id"]
        ops = r["data"]["attributes"].get("uploadOperations", [])

        for op in ops:
            url = op["url"]
            op_headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
            chunk = data[op["offset"]:op["offset"] + op["length"]]
            resp = requests.put(url, headers=op_headers, data=chunk)
            if resp.status_code >= 400:
                print(f"    Chunk upload failed: {resp.status_code}")

        patch(f"/appScreenshots/{ss_id}", {
            "data": {
                "type": "appScreenshots", "id": ss_id,
                "attributes": {"uploaded": True, "sourceFileChecksum": checksum}
            }
        })
        print(f"    Done: {filename}")


# ── 4. Submit for review ──
def submit_for_review():
    print("\n[4] Submitting for review...")
    r = post("/reviewSubmissions", {
        "data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}}
            }
        }
    })
    if r:
        sub_id = r["data"]["id"]
        print(f"  Created review submission: {sub_id}")

        # Add all versions
        for platform in ["MAC_OS", "IOS"]:
            vr = get(f"/apps/{APP_ID}/appStoreVersions?filter[platform]={platform}")
            for v in vr.get("data", []):
                if v["attributes"]["versionString"] == "1.0.0":
                    post(f"/reviewSubmissionItems", {
                        "data": {
                            "type": "reviewSubmissionItems",
                            "relationships": {
                                "reviewSubmission": {
                                    "data": {"type": "reviewSubmissions", "id": sub_id}
                                },
                                "appStoreVersion": {
                                    "data": {"type": "appStoreVersions", "id": v["id"]}
                                }
                            }
                        }
                    })
                    print(f"  Added {platform} version to submission")

        # Submit
        result = patch(f"/reviewSubmissions/{sub_id}", {
            "data": {
                "type": "reviewSubmissions", "id": sub_id,
                "attributes": {"submitted": True}
            }
        })
        if result:
            print(f"  Submitted for review!")
        else:
            print(f"  Submit failed - may need manual submission")
    else:
        print("  Could not create review submission")


def main():
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_DIR = os.path.dirname(SCRIPT_DIR)

    print("=" * 50)
    print("  CLI Pulse - Resubmit to App Store")
    print("=" * 50)

    # Test connection
    r = get(f"/apps/{APP_ID}")
    print(f"  Connected: {r['data']['attributes']['name']}")

    # Step 1: Cancel reviews
    cancel_reviews()
    print("  Waiting 5s for state to propagate...")
    time.sleep(5)

    # Step 2: Get version IDs and select builds
    mac_vid = None
    ios_vid = None
    for platform in ["MAC_OS", "IOS"]:
        r = get(f"/apps/{APP_ID}/appStoreVersions?filter[platform]={platform}")
        for v in r.get("data", []):
            if v["attributes"]["versionString"] == "1.0.0":
                state = v["attributes"]["appStoreState"]
                print(f"\n  {platform} v1.0.0: state={state} id={v['id']}")
                if platform == "MAC_OS":
                    mac_vid = v["id"]
                else:
                    ios_vid = v["id"]

    # Try to select build 3
    if mac_vid:
        select_build(mac_vid, "macOS")
    if ios_vid:
        select_build(ios_vid, "iOS")

    # Step 3: Update screenshots
    # macOS
    if mac_vid:
        r = get(f"/appStoreVersions/{mac_vid}/appStoreVersionLocalizations")
        for loc in r.get("data", []):
            if loc["attributes"]["locale"] == "en-US":
                mac_loc = loc["id"]
                mac_dir = os.path.expanduser("~/Desktop/CLIPulseBar-Screenshots")
                if os.path.isdir(mac_dir):
                    files = sorted([os.path.join(mac_dir, f) for f in os.listdir(mac_dir) if f.endswith("_2880x1800.png")])
                    if files:
                        upload_screenshots(mac_loc, files, "APP_DESKTOP")

    # iOS
    if ios_vid:
        r = get(f"/appStoreVersions/{ios_vid}/appStoreVersionLocalizations")
        for loc in r.get("data", []):
            if loc["attributes"]["locale"] == "en-US":
                ios_loc = loc["id"]

                # iPhone 6.7"
                ios_dir = os.path.join(PROJECT_DIR, "build/ios-screenshots")
                if os.path.isdir(ios_dir):
                    files = sorted([os.path.join(ios_dir, f) for f in os.listdir(ios_dir) if f.endswith(".png")])
                    if files:
                        upload_screenshots(ios_loc, files, "APP_IPHONE_67")

                # iPad 12.9"
                ipad_dir = os.path.join(PROJECT_DIR, "build/ipad-screenshots")
                if os.path.isdir(ipad_dir):
                    files = sorted([os.path.join(ipad_dir, f) for f in os.listdir(ipad_dir) if f.endswith(".png")])
                    if files:
                        upload_screenshots(ios_loc, files, "APP_IPAD_PRO_3GEN_129")

    # Step 4: Submit for review
    submit_for_review()

    print("\n" + "=" * 50)
    print("  Done!")
    print("=" * 50)


if __name__ == "__main__":
    main()
