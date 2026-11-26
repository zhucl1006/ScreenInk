#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ScreenInk"
BUNDLE_ID="com.screenink.overlay"
APP_VERSION="${APP_VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_PATH="$BUILD_DIR/${APP_NAME}-macOS.zip"
DMG_PATH="$BUILD_DIR/${APP_NAME}-macOS.dmg"

echo "==> 1. Building $APP_NAME ($APP_VERSION) in Release mode..."
cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Error: Binary not found at $BIN_PATH"
  exit 1
fi

echo "==> 2. Generating AppIcon.icns..."
ICON_WORK="$BUILD_DIR/icon_work"
ICONSET_DIR="$ICON_WORK/AppIcon.iconset"
rm -rf "$ICON_WORK"
mkdir -p "$ICONSET_DIR"

swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICON_WORK/base_1024.png"

for sz in 16 32 128 256 512; do
  sips -z "$sz" "$sz" "$ICON_WORK/base_1024.png" --out "$ICONSET_DIR/icon_${sz}x${sz}.png" >/dev/null
  double=$((sz * 2))
  sips -z "$double" "$double" "$ICON_WORK/base_1024.png" --out "$ICONSET_DIR/icon_${sz}x${sz}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$ICON_WORK/AppIcon.icns"

echo "==> 3. Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$ICON_WORK/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> 4. Ad-hoc signing $APP_BUNDLE..."
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> 5. Creating distributable ZIP archive..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> 6. Creating distributable DMG installer..."
DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$ICON_WORK" "$DMG_STAGING"

echo "==> Build complete:"
echo "    App: $APP_BUNDLE"
echo "    ZIP: $ZIP_PATH"
echo "    DMG: $DMG_PATH"
