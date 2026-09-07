#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'BUILD BLOCKED: requires macOS with Xcode and the iPhoneOS SDK. No IPA was generated.' >&2
  exit 2
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode_26.6.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
fi
command -v xcodebuild >/dev/null || { echo 'Install full Xcode (Command Line Tools alone is insufficient).' >&2; exit 2; }
command -v python3 >/dev/null || { echo 'python3 is required for integrity verification.' >&2; exit 2; }
python3 "$ROOT/scripts/verify-source.py"
mkdir -p "$ROOT/build" "$ROOT/dist"
RUN="$(mktemp -d "$ROOT/build/run.XXXXXX")"
exec > >(tee "$RUN/build.log") 2>&1
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
xcodebuild archive \
  -project "$ROOT/WorkPlot/WorkPlot.xcodeproj" \
  -scheme WorkPlot -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$RUN/WorkPlot.xcarchive" \
  -derivedDataPath "$RUN/DerivedData" \
  CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  CURRENT_PROJECT_VERSION=2026090702
APP="$RUN/WorkPlot.xcarchive/Products/Applications/WorkPlot.app"
test -d "$APP"
plutil -lint "$APP/Info.plist"
IDENTITY="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
[[ "$IDENTITY" == com.apple.mobile.MobileHouseArrest ]] || { echo "Unexpected identity: $IDENTITY"; exit 3; }
xcrun lipo "$APP/WorkPlot" -verify_arch arm64
mkdir -p "$RUN/package/Payload"
ditto "$APP" "$RUN/package/Payload/WorkPlot.app"
(cd "$RUN/package" && /usr/bin/zip -qry "$RUN/WorkPlot-CanvasTest.ipa" Payload)
/usr/bin/unzip -tq "$RUN/WorkPlot-CanvasTest.ipa"
cp "$RUN/WorkPlot-CanvasTest.ipa" "$ROOT/dist/WorkPlot-CanvasTest.ipa"
if [[ -d "$RUN/WorkPlot.xcarchive/dSYMs" ]]; then
  ditto -c -k --keepParent "$RUN/WorkPlot.xcarchive/dSYMs" "$ROOT/dist/WorkPlot-CanvasTest-dSYMs.zip"
fi
shasum -a 256 "$ROOT/dist/WorkPlot-CanvasTest.ipa" | tee "$ROOT/dist/WorkPlot-CanvasTest.ipa.sha256"
echo "Generated unsigned IPA: $ROOT/dist/WorkPlot-CanvasTest.ipa"
echo "Build log: $RUN/build.log"
echo 'Signing/installation and physical phone validation remain to be performed. Preserve the bundle identifier.'
