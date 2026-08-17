#!/bin/bash
# dist/MenuBarTidy-<version>.zip を notarize して staple 済みの zip に差し替える
#
# 資格情報は `xcrun notarytool store-credentials <プロファイル名>` で作った
# keychain プロファイル（既定 "notary"）を使う。
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-notary}"
APP="Build/Build/Products/Release/MenuBar Tidy.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="dist/MenuBarTidy-$VERSION.zip"
[ -f "$ZIP" ] || { echo "NG: $ZIP がない（先に mise run release:zip）"; exit 1; }

xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# staple は .app に対して行う。zip の中身を展開して貼り、貼った方を再 zip する。
STAPLE_DIR=$(mktemp -d)
ditto -x -k "$ZIP" "$STAPLE_DIR"
xcrun stapler staple "$STAPLE_DIR/MenuBar Tidy.app"

assess=$(spctl --assess --type execute -vv "$STAPLE_DIR/MenuBar Tidy.app" 2>&1)
case "$assess" in
    *"Notarized Developer ID"*) ;;
    *) echo "NG: Gatekeeper 評価が通らない: $assess"; exit 1 ;;
esac

/bin/rm -f "$ZIP" 2>/dev/null || true
ditto -c -k --sequesterRsrc --keepParent "$STAPLE_DIR/MenuBar Tidy.app" "$ZIP"
/bin/rm -rf "$STAPLE_DIR" 2>/dev/null || true

echo "OK: staple 済み $ZIP"
echo "次: scripts/publish-release.sh"
