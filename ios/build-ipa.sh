#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodegen >/dev/null || { echo 'Install XcodeGen on the Mac build host first.' >&2; exit 1; }
xcodegen generate
mkdir -p build
xcrun swiftc SiteWatch/Models.swift Tests/main.swift -o build/topology-tests
./build/topology-tests
xcodebuild -project SiteWatch.xcodeproj -scheme SiteWatch -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
APP='build/DerivedData/Build/Products/Release-iphoneos/SiteWatch.app'
test -x "$APP/SiteWatch"
xcrun lipo "$APP/SiteWatch" -verify_arch arm64
plutil -lint "$APP/Info.plist"
STAGE=$(mktemp -d "$PWD/build/ipa.XXXXXX")
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/SiteWatch.app"
ditto -c -k --keepParent "$STAGE/Payload" build/SiteWatch-unsigned.ipa
echo 'Built ios/build/SiteWatch-unsigned.ipa — must be signed before installation.'
