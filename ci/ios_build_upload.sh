#!/bin/bash
# Archive and upload to TestFlight. Tries the build with the widget
# extension first (ad-hoc signed so the App Group entitlement is kept, then
# unsigned), and falls back to the app without widgets so a build always
# reaches TestFlight.
set -u
LOG="$PWD/build.log"
OPTS="$RUNNER_TEMP/ExportOptions.plist"
cat > "$OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$APPLE_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

ARCHIVE="$RUNNER_TEMP/Runner.xcarchive"

archive() {
  local dir=$1 mode=$2
  rm -rf "$ARCHIVE"
  local sign
  if [ "$mode" = adhoc ]; then
    sign=(CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO "PROVISIONING_PROFILE_SPECIFIER=")
  else
    sign=(CODE_SIGNING_ALLOWED=NO)
  fi
  (cd "$dir" && xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release \
      -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" "${sign[@]}" archive) >> "$LOG" 2>&1
  local ok=$?
  grep -E ' error: |\*\* ARCHIVE' "$LOG" | tail -15
  [ $ok -eq 0 ] && [ -d "$ARCHIVE" ] || return 1
  echo "--- App entitlements in archive:" | tee -a "$LOG"
  codesign -d --entitlements - "$ARCHIVE/Products/Applications/Runner.app" 2>&1 | tee -a "$LOG" | head -20
  ls "$ARCHIVE/Products/Applications/Runner.app/PlugIns" 2>/dev/null | tee -a "$LOG"
  return 0
}

upload() {
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTS" \
    -exportPath "$RUNNER_TEMP/export" -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" >> "$LOG" 2>&1
  local ok=$?
  grep -E 'error|EXPORT|Upload|upload' "$LOG" | tail -15
  return $ok
}

attempt() {
  echo "=== Attempt: $1 ($2)" | tee -a "$LOG"
  if archive "$1" "$2" && upload; then
    echo "=== Uploaded with: $1 ($2)" | tee -a "$LOG"
    return 0
  fi
  echo "=== Failed: $1 ($2)" | tee -a "$LOG"
  return 1
}

if [ -d build_ios/ios/ExpenseWidget ]; then
  attempt build_ios/ios adhoc || attempt build_ios/ios unsigned || attempt build_ios/ios_plain unsigned
else
  attempt build_ios/ios unsigned
fi
