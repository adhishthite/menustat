#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-MenuStat}"
BUNDLE_ID="${BUNDLE_ID:-com.adhishthite.MenuStat}"
TEAM_ID="${TEAM_ID:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
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
DMG_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION.dmg"
NOTARY_ZIP_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION-notary.zip"
CURRENT_YEAR="$(date +%Y)"

require_signing_identity() {
  if [[ -z "$SIGNING_IDENTITY" && -n "$TEAM_ID" ]]; then
    SIGNING_IDENTITY="$(
      /usr/bin/security find-identity -v -p codesigning |
        /usr/bin/sed -nE "s/.*\"(Developer ID Application: .+ \\($TEAM_ID\\))\".*/\\1/p" |
        /usr/bin/head -n 1
    )"
  fi

  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Missing signing configuration." >&2
    echo "Set SIGNING_IDENTITY, or set TEAM_ID so the script can find a Developer ID Application identity." >&2
    exit 1
  fi

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

submit_for_notarization() {
  local artifact_path="$1"
  local artifact_name
  artifact_name="$(basename "$artifact_path")"

  if [[ -z "$TEAM_ID" ]]; then
    echo "Missing TEAM_ID for notarization." >&2
    exit 1
  fi

  echo "Submitting $artifact_name to Apple notary service with keychain profile: $NOTARY_PROFILE"
  /usr/bin/xcrun notarytool submit "$artifact_path" \
    --keychain-profile "$NOTARY_PROFILE" \
    --team-id "$TEAM_ID" \
    --wait
}

package_dmg() {
  local output_path="$1"
  local dmg_root="$WORK_DIR/dmg-root"

  rm -rf "$dmg_root"
  rm -f "$output_path"
  mkdir -p "$dmg_root"
  /usr/bin/ditto "$APP_BUNDLE" "$dmg_root/$APP_NAME.app"
  /bin/ln -s /Applications "$dmg_root/Applications"

  /usr/bin/hdiutil create \
    -volname "$APP_NAME $MARKETING_VERSION" \
    -srcfolder "$dmg_root" \
    -ov \
    -format UDZO \
    "$output_path"

  for attempt in 1 2 3; do
    if /usr/bin/hdiutil verify "$output_path"; then
      return
    fi
    sleep "$attempt"
  done

  /usr/bin/hdiutil verify "$output_path"
}

sign_dmg() {
  local dmg_path="$1"

  echo "Signing DMG with $SIGNING_IDENTITY"
  /usr/bin/codesign \
    --force \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$dmg_path"
}

require_signing_identity

rm -rf "$WORK_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH" "$DMG_PATH" "$NOTARY_ZIP_PATH"

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
  package_zip "$NOTARY_ZIP_PATH"
  submit_for_notarization "$NOTARY_ZIP_PATH"

  echo "Stapling notarization ticket to app"
  /usr/bin/xcrun stapler staple "$APP_BUNDLE"
  /usr/sbin/spctl --assess --type execute --verbose "$APP_BUNDLE"
  rm -f "$NOTARY_ZIP_PATH"
else
  echo "Skipping notarization because NOTARY_PROFILE is not set."
  echo "After storing credentials, rerun with: NOTARY_PROFILE=<profile> make package-release"
fi

package_zip "$ZIP_PATH"
package_dmg "$DMG_PATH"
sign_dmg "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  submit_for_notarization "$DMG_PATH"
  echo "Stapling notarization ticket to DMG"
  /usr/bin/xcrun stapler staple "$DMG_PATH"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
fi

echo "Release app: $APP_BUNDLE"
echo "Release zip: $ZIP_PATH"
echo "Release dmg: $DMG_PATH"
