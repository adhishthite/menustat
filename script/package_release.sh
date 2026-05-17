#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-MenuStat}"
BUNDLE_ID="${BUNDLE_ID:-com.adhishthite.MenuStat}"
TEAM_ID="${TEAM_ID:-ATQ45ZSG3M}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Adhish Thite (${TEAM_ID})}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-13.0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$DIST_DIR/work"
APP_BUNDLE="$WORK_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"
ZIP_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION.zip"
NOTARY_ZIP_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION-notary.zip"
CURRENT_YEAR="$(date +%Y)"

require_signing_identity() {
  if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$SIGNING_IDENTITY"; then
    echo "Missing signing identity: $SIGNING_IDENTITY" >&2
    echo "Open Xcode > Settings > Accounts > Manage Certificates and add Developer ID Application." >&2
    exit 1
  fi
}

write_info_plist() {
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSArchitecturePriority</key>
  <array>
    <string>arm64</string>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright $CURRENT_YEAR Adhish Thite. All rights reserved.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

package_zip() {
  local output_path="$1"
  rm -f "$output_path"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$output_path"
}

require_signing_identity

rm -rf "$WORK_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH" "$NOTARY_ZIP_PATH"

echo "Building $APP_NAME $MARKETING_VERSION ($BUILD_NUMBER)"
swift build -c release

cp "$ROOT_DIR/.build/release/$APP_NAME" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
write_info_plist

echo "Signing with $SIGNING_IDENTITY"
/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$APP_BUNDLE"

echo "Verifying signature"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ -n "$NOTARY_PROFILE" ]]; then
  echo "Submitting to Apple notary service with keychain profile: $NOTARY_PROFILE"
  package_zip "$NOTARY_ZIP_PATH"
  /usr/bin/xcrun notarytool submit "$NOTARY_ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --team-id "$TEAM_ID" \
    --wait

  echo "Stapling notarization ticket"
  /usr/bin/xcrun stapler staple "$APP_BUNDLE"
  /usr/sbin/spctl --assess --type execute --verbose "$APP_BUNDLE"
  rm -f "$NOTARY_ZIP_PATH"
else
  echo "Skipping notarization because NOTARY_PROFILE is not set."
  echo "After storing credentials, rerun with: NOTARY_PROFILE=<profile> make package-release"
fi

package_zip "$ZIP_PATH"

echo "Release app: $APP_BUNDLE"
echo "Release zip: $ZIP_PATH"
