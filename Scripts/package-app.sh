#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="EchoType"
APP_BUNDLE="dist/${APP_NAME}.app"
ZIP_PATH="dist/${APP_NAME}.zip"
VERIFY_DIR="dist/verify-extracted"
ICONSET_DIR="dist/AppIcon.iconset"

rm -rf "$APP_BUNDLE" "$ZIP_PATH" "$VERIFY_DIR" "$ICONSET_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "dist"

swift build --configuration release --product EchoTypeApp
install -m 755 ".build/release/EchoTypeApp" "$APP_BUNDLE/Contents/MacOS/EchoTypeApp"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

resource_bundles=()
while IFS= read -r bundle_path; do
    resource_bundles+=("$bundle_path")
done < <(find .build/release -maxdepth 1 -type d -name '*.bundle' -print)
if ((${#resource_bundles[@]} == 0)); then
    printf 'No SwiftPM resource bundles found in .build/release\n' >&2
    exit 1
fi
for bundle_path in "${resource_bundles[@]}"; do
    cp -R "$bundle_path" "$APP_BUNDLE/Contents/Resources/"
done

swift Scripts/create-app-icon.swift "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"

mkdir -p "$VERIFY_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"
EXTRACTED_APP="$VERIFY_DIR/${APP_NAME}.app"
test -x "$EXTRACTED_APP/Contents/MacOS/EchoTypeApp"
plutil -lint "$EXTRACTED_APP/Contents/Info.plist"
codesign --verify --deep --strict "$EXTRACTED_APP"
test -n "$(find "$EXTRACTED_APP/Contents/Resources" -maxdepth 1 -type d -name '*.bundle' -print -quit)"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
printf 'Packaged and verified: %s\n' "$ZIP_PATH"
