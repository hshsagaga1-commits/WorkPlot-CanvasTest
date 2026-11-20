#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
out="${1:-$project_root/build/output}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
exec > >(tee "$out/build.log") 2>&1

if ! command -v xcodebuild >/dev/null || ! xcrun --sdk iphoneos --show-sdk-path >/dev/null; then
    echo "O build do IPA requer macOS, Xcode e SDK iPhoneOS."
    exit 1
fi

revision="$(git -C "$project_root" rev-parse HEAD 2>/dev/null || echo local)"
work="$(mktemp -d "${TMPDIR:-/tmp}/resolutionlab.XXXXXX")"
trap 'rm -rf "$work"' EXIT

{
    xcodebuild -version
    printf 'SDK iPhoneOS %s\n' "$(xcrun --sdk iphoneos --show-sdk-version)"
    printf 'Revisão %s\n' "$revision"
} | tee "$out/build-info.txt"

xcodebuild -project ResolutionLabObserver.xcodeproj \
    -scheme ResolutionLabObserver \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$work/DerivedData" \
    ARCHS=arm64 \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    RESOLUTIONLAB_SOURCE_COMMIT="$revision" \
    clean build

app="$work/DerivedData/Build/Products/Release-iphoneos/ResolutionLabObserver.app"
architecture="$(xcrun lipo -archs "$app/ResolutionLabObserver")"
printf 'Arquitetura %s\n' "$architecture"
test "$architecture" = arm64
xcrun vtool -show-build "$app/ResolutionLabObserver" | tee "$out/macho.txt"
grep -qE 'platform[[:space:]]+IOS[[:space:]]*$' "$out/macho.txt"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :RLSourceCommit' "$app/Info.plist"
test ! -e "$app/embedded.mobileprovision"

mkdir -p "$work/package/Payload"
ditto "$app" "$work/package/Payload/ResolutionLabObserver.app"
ipa="ResolutionLab-Observer-v0.2.0.ipa"
(
    cd "$work/package"
    zip -X -q -r "$work/$ipa" Payload
)
unzip -tq "$work/$ipa"
mv "$work/$ipa" "$out/$ipa"
(
    cd "$out"
    shasum -a 256 "$ipa" | tee SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
