#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project SiteWatch.xcodeproj -scheme SiteWatch -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/Simulator CODE_SIGNING_ALLOWED=NO build
UDID=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; devices=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d.get("isAvailable") and d["name"].startswith("iPhone")]; assert devices, "No available iPhone simulator"; print(devices[0]["udid"])')
STATE=$(xcrun simctl list devices --json | python3 -c 'import json,sys; target=sys.argv[1]; print(next(d["state"] for group in json.load(sys.stdin)["devices"].values() for d in group if d["udid"]==target))' "$UDID")
if [ "$STATE" != 'Booted' ]; then xcrun simctl boot "$UDID"; fi
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" build/Simulator/Build/Products/Debug-iphonesimulator/SiteWatch.app
xcrun simctl launch "$UDID" app.sitewatch.networkmonitor
sleep 3
xcrun simctl io "$UDID" screenshot build/preview.png
