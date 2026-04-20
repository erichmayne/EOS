# RunMatch — Build & Deploy to App Store Connect

## Prerequisites

- Xcode installed with signing certificates
- Apple ID signed in: **Xcode → Settings → Accounts** (re-sign-in if session expires)
- Development Team ID: `3W9Q24UY7J`
- Bundle ID: `com.emayne.eos` (production), `com.emayne.eos.dev` (debug)
- Scheme name: `morning-would`
- Project file: `Eos.xcodeproj`

---

## Step 1: Set Version & Build Number

In `Eos.xcodeproj/project.pbxproj`, update these (6 occurrences each):

```
MARKETING_VERSION = 2.0;        # App Store version (e.g., 2.0, 2.1)
CURRENT_PROJECT_VERSION = 1;    # Build number (increment for each upload under same version)
```

**Rule:** App Store rejects a version number that's already been approved. Bump `MARKETING_VERSION` for new versions, bump `CURRENT_PROJECT_VERSION` for re-uploads under the same version.

---

## Step 2: Verify Key Config

Before building, confirm these are correct:

**API URL** (`morning-would/StripeConfig.swift`):
```swift
static let backendURL = URL(string: "https://api.runmatch.io")!
```

**QuickPose SDK Keys** (`morning-would/ContentView.swift`):
```swift
#if DEBUG
var quickPose = QuickPose(sdkKey: "01KMGZKANM1NARDA4QEC0WN06T")  // dev key
#else
var quickPose = QuickPose(sdkKey: "01KMHEK59VAAEJXW58WV974VD0")  // prod key
#endif
```

Archive builds use Release configuration, so the `#else` (prod) key is used automatically.

---

## Step 3: Archive

```bash
cd /Users/emayne/morning-would

xcodebuild \
  -project Eos.xcodeproj \
  -scheme "morning-would" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath /Users/emayne/morning-would/build/ARCHIVE_NAME.xcarchive \
  archive \
  DEVELOPMENT_TEAM=3W9Q24UY7J \
  CODE_SIGN_STYLE=Automatic
```

Replace `ARCHIVE_NAME` with something descriptive (e.g., `RunMatch20` for v2.0).

**Expected output:** `** ARCHIVE SUCCEEDED **`

**Common failures:**
- `CodeSign failed` → Re-sign in Xcode → Settings → Accounts
- `Signing requires a development team` → Make sure `DEVELOPMENT_TEAM=3W9Q24UY7J` is passed
- Build errors → Fix code first, archive is Release config (stricter than Debug)

**Build time:** ~2.5-3 minutes typically.

---

## Step 4: Create Export Options Plist

Create `/tmp/ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>3W9Q24UY7J</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>destination</key>
    <string>upload</string>
</dict>
</plist>
```

This file can be reused for every upload. Only create it once.

---

## Step 5: Upload to App Store Connect

```bash
xcodebuild \
  -exportArchive \
  -archivePath /Users/emayne/morning-would/build/ARCHIVE_NAME.xcarchive \
  -exportOptionsPlist /tmp/ExportOptions.plist \
  -exportPath /Users/emayne/morning-would/build/export_OUTPUT \
  -allowProvisioningUpdates
```

**Expected output:** `Upload succeeded.` followed by `** EXPORT SUCCEEDED **`

**Common failures:**
- `Your session has expired` → Go to Xcode → Settings → Accounts, re-sign in with Apple ID, then retry
- `CFBundleShortVersionString must contain a higher version` → The version number is already approved on App Store. Bump `MARKETING_VERSION` higher.
- `Failed to Use Accounts` → Same as session expired. Re-authenticate in Xcode.

**Upload time:** ~1-2 minutes.

**Warnings to ignore:**
- `Upload Symbols Failed for QuickPoseCore.framework` — This is a third-party SDK, no dSYM available. Non-blocking.
- `The app icon set has an unassigned child` — Cosmetic Xcode warning, doesn't affect the build.

---

## Step 6: Post-Upload

1. **Wait 5-15 minutes** for App Store Connect to finish processing the build
2. Go to **App Store Connect → Your App → TestFlight** to see the build appear
3. **Export Compliance:** Click "Manage" next to the compliance warning:
   - "Does your app use encryption?" → **Yes**
   - "Does your app qualify for exemptions?" → **Yes** (standard HTTPS/TLS only)
4. The build is now available to submit for App Store Review or distribute via TestFlight

---

## Step 7: Submit for Review (if ready)

1. Go to **App Store Connect → Your App → App Store tab**
2. Select the new build under "Build"
3. Fill in "What's New" text
4. Update screenshots if needed (screenshots are per-version, not per-build)
5. Click "Submit for Review"

---

## Quick Reference — Full Command Sequence

```bash
# 1. Archive
cd /Users/emayne/morning-would
xcodebuild -project Eos.xcodeproj -scheme "morning-would" -configuration Release -destination "generic/platform=iOS" -archivePath /Users/emayne/morning-would/build/RunMatch20.xcarchive archive DEVELOPMENT_TEAM=3W9Q24UY7J CODE_SIGN_STYLE=Automatic

# 2. Upload
xcodebuild -exportArchive -archivePath /Users/emayne/morning-would/build/RunMatch20.xcarchive -exportOptionsPlist /tmp/ExportOptions.plist -exportPath /Users/emayne/morning-would/build/exportRM20 -allowProvisioningUpdates
```

---

## Backend Deployment (for reference)

After code changes to `backend/server.js`:

```bash
scp /Users/emayne/morning-would/backend/server.js root@143.198.143.204:/home/user/morning-would-payments/server.js
ssh root@143.198.143.204 'pm2 restart eos-backend'
```

After changes to web files:

```bash
scp /Users/emayne/morning-would/branding/eos-website-improved.html root@143.198.143.204:/var/www/live-eos/index.html
scp /Users/emayne/morning-would/web/FILE.html root@143.198.143.204:/var/www/live-eos/FILE.html
```

---

## Server Details

- **IP:** `143.198.143.204`
- **SSH:** `ssh root@143.198.143.204`
- **Backend path:** `/home/user/morning-would-payments/`
- **Web path:** `/var/www/live-eos/`
- **PM2 process:** `eos-backend`
- **Domain:** `runmatch.io` / `api.runmatch.io`
