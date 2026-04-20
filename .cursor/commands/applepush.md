---
description: Archive and upload the iOS app to App Store Connect
---

# Apple Push — Build & Upload to App Store Connect

Follow these steps exactly in order. Do not skip any step.

## 1. Read Current Version

Read `Eos.xcodeproj/project.pbxproj` and find `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Report them to the user and ask what version/build to use, or if the user already specified, set them.

Update all 6 occurrences of each in the file.

## 2. Verify Config

Confirm these are correct before building:
- `morning-would/StripeConfig.swift` → `backendURL` should be `https://api.runmatch.io`
- `morning-would/ContentView.swift` → `#if DEBUG` / `#else` QuickPose SDK keys present
- Dev key: `01KMGZKANM1NARDA4QEC0WN06T`
- Prod key: `01KMHEK59VAAEJXW58WV974VD0`

## 3. Archive

Run this command with block_until_ms of 600000:

```bash
cd /Users/emayne/morning-would && xcodebuild -project Eos.xcodeproj -scheme "morning-would" -configuration Release -destination "generic/platform=iOS" -archivePath /Users/emayne/morning-would/build/ARCHIVE_NAME.xcarchive archive DEVELOPMENT_TEAM=3W9Q24UY7J CODE_SIGN_STYLE=Automatic 2>&1 | grep -E "error:|ARCHIVE SUCCEEDED|ARCHIVE FAILED" | tail -10
```

Replace ARCHIVE_NAME with something descriptive like RunMatch20 for v2.0.

If ARCHIVE FAILED, read the full error output and fix before retrying.

## 4. Create Export Options (if not exists)

Check if `/tmp/ExportOptions.plist` exists. If not, create it:

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

## 5. Upload

Run with block_until_ms of 300000:

```bash
cd /Users/emayne/morning-would && xcodebuild -exportArchive -archivePath /Users/emayne/morning-would/build/ARCHIVE_NAME.xcarchive -exportOptionsPlist /tmp/ExportOptions.plist -exportPath /Users/emayne/morning-would/build/export_ARCHIVE_NAME -allowProvisioningUpdates 2>&1 | tail -10
```

## 6. Handle Failures

- **"Your session has expired"** → Tell the user to go to Xcode → Settings → Accounts and re-sign in with their Apple ID. Then retry step 5.
- **"CFBundleShortVersionString must contain a higher version"** → The version is already approved. Bump MARKETING_VERSION higher and redo from step 1.
- **"CodeSign failed"** → Re-sign in Xcode Accounts, then redo from step 3.

## 7. Confirm Success

Expected output includes `Upload succeeded.` and `** EXPORT SUCCEEDED **`.

Warnings about QuickPoseCore.framework dSYM are expected and non-blocking — ignore them.

Tell the user the build is uploaded and will appear in App Store Connect / TestFlight within 5-15 minutes. Remind them about Export Compliance (select "Yes" for standard encryption exemption).
