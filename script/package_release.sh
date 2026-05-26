#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-MenuStat}"
APP_EXECUTABLE_NAME="${APP_EXECUTABLE_NAME:-MenuStatApp}"
CLI_NAME="${CLI_NAME:-menustat}"
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
APP_BINARY="$APP_MACOS/$APP_EXECUTABLE_NAME"
APP_CLI_BINARY="$APP_MACOS/$CLI_NAME"
CLI_WORK_DIR="$WORK_DIR/cli"
CLI_BINARY="$CLI_WORK_DIR/$CLI_NAME"
CLI_README="$CLI_WORK_DIR/README.txt"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"
ZIP_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION.zip"
DMG_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION.dmg"
CLI_ZIP_PATH="$DIST_DIR/MenuStatCLI-$MARKETING_VERSION.zip"
NOTARY_ZIP_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION-notary.zip"
CLI_NOTARY_ZIP_PATH="$DIST_DIR/MenuStatCLI-$MARKETING_VERSION-notary.zip"
CURRENT_YEAR="$(date +%Y)"
BUILD_UNIVERSAL="${BUILD_UNIVERSAL:-1}"

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
  <string>$APP_EXECUTABLE_NAME</string>
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
    <string>x86_64</string>
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
  COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent --norsrc "$APP_BUNDLE" "$output_path"
}

package_cli_zip() {
  local output_path="$1"
  rm -f "$output_path"
  COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc "$CLI_WORK_DIR" "$output_path"
}

detach_image_devices() {
  local image_path="$1"
  local devices

  devices="$(
    /usr/bin/hdiutil info |
      /usr/bin/awk -v image="$image_path" '
        $1 == "image-path" {
          current = substr($0, index($0, ":") + 2)
          in_image = (current == image)
          next
        }
        /^=+/ { in_image = 0 }
        in_image && $1 ~ /^\/dev\/disk/ { print $1 }
      '
  )"

  while IFS= read -r device; do
    [[ -n "$device" ]] && /usr/bin/hdiutil detach "$device" >/dev/null 2>&1 || true
  done <<<"$devices"
}

write_cli_readme() {
  cat >"$CLI_README" <<README
MenuStat CLI $MARKETING_VERSION

Install:
  sudo install -m 755 menustat /usr/local/bin/menustat

Examples:
  menustat
  menustat snapshot
  menustat snapshot --json
  menustat top --by cpu --limit 5
  menustat fans

The CLI is observe-only. It reads the same Apple Silicon telemetry as MenuStat.app
but does not launch, quit, or configure the menu-bar app.
README
}

build_binaries() {
  if [[ "$BUILD_UNIVERSAL" == "1" ]]; then
    local arm_dir x86_dir app_arm app_x86 cli_arm cli_x86
    app_arm="$WORK_DIR/$APP_EXECUTABLE_NAME-arm64"
    app_x86="$WORK_DIR/$APP_EXECUTABLE_NAME-x86_64"
    cli_arm="$WORK_DIR/$CLI_NAME-arm64"
    cli_x86="$WORK_DIR/$CLI_NAME-x86_64"

    arm_dir="$(swift build -c release --triple arm64-apple-macos13.0 --show-bin-path)"
    x86_dir="$(swift build -c release --triple x86_64-apple-macos13.0 --show-bin-path)"

    echo "Building $APP_NAME $MARKETING_VERSION ($BUILD_NUMBER) for arm64"
    swift build -c release --triple arm64-apple-macos13.0 --product "$APP_NAME"
    cp "$arm_dir/$APP_NAME" "$app_arm"
    swift build -c release --triple arm64-apple-macos13.0 --product "$CLI_NAME"
    cp "$arm_dir/$CLI_NAME" "$cli_arm"
    echo "Building $APP_NAME $MARKETING_VERSION ($BUILD_NUMBER) for x86_64 compatibility alert"
    swift build -c release --triple x86_64-apple-macos13.0 --product "$APP_NAME"
    cp "$x86_dir/$APP_NAME" "$app_x86"
    swift build -c release --triple x86_64-apple-macos13.0 --product "$CLI_NAME"
    cp "$x86_dir/$CLI_NAME" "$cli_x86"
    /usr/bin/lipo -create "$app_arm" "$app_x86" -output "$APP_BINARY"
    /usr/bin/lipo -create "$cli_arm" "$cli_x86" -output "$CLI_BINARY"
  else
    echo "Building $APP_NAME $MARKETING_VERSION ($BUILD_NUMBER)"
    swift build -c release --product "$APP_NAME"
    cp "$ROOT_DIR/.build/release/$APP_NAME" "$APP_BINARY"
    swift build -c release --product "$CLI_NAME"
    cp "$ROOT_DIR/.build/release/$CLI_NAME" "$CLI_BINARY"
  fi

  cp "$CLI_BINARY" "$APP_CLI_BINARY"
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
    detach_image_devices "$output_path"
    sleep "$attempt"
  done

  detach_image_devices "$output_path"
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
mkdir -p "$CLI_WORK_DIR"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH" "$DMG_PATH" "$CLI_ZIP_PATH" "$NOTARY_ZIP_PATH" "$CLI_NOTARY_ZIP_PATH"

build_binaries
chmod +x "$APP_BINARY" "$APP_CLI_BINARY" "$CLI_BINARY"
cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
write_info_plist
write_cli_readme

echo "Signing CLI with $SIGNING_IDENTITY"
/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$CLI_BINARY"

/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$APP_CLI_BINARY"

echo "Signing with $SIGNING_IDENTITY"
/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$APP_BUNDLE"

echo "Verifying signature"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/codesign --verify --strict --verbose=2 "$CLI_BINARY"

if [[ -n "$NOTARY_PROFILE" ]]; then
  package_zip "$NOTARY_ZIP_PATH"
  submit_for_notarization "$NOTARY_ZIP_PATH"

  echo "Stapling notarization ticket to app"
  /usr/bin/xcrun stapler staple "$APP_BUNDLE"
  /usr/sbin/spctl --assess --type execute --verbose "$APP_BUNDLE"
  rm -f "$NOTARY_ZIP_PATH"

  package_cli_zip "$CLI_ZIP_PATH"
  submit_for_notarization "$CLI_ZIP_PATH"
  /usr/bin/codesign --verify --strict --verbose=2 "$CLI_BINARY"
  rm -f "$CLI_NOTARY_ZIP_PATH"
else
  echo "Skipping notarization because NOTARY_PROFILE is not set."
  echo "After storing credentials, rerun with: NOTARY_PROFILE=<profile> make package-release"
  package_cli_zip "$CLI_ZIP_PATH"
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
echo "Release CLI: $CLI_BINARY"
echo "Release zip: $ZIP_PATH"
echo "Release CLI zip: $CLI_ZIP_PATH"
echo "Release dmg: $DMG_PATH"
