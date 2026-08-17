#!/bin/bash
# Release ビルドを配布適格か検証して dist/MenuBarTidy-<version>.zip を作る
#
# Release 構成は Developer ID + --timestamp + get-task-allow なしで署名するよう
# project.pbxproj に設定してあるので、ここでの再署名は不要。代わりに配布要件を
# 満たしているかを検証する（満たさないと notarize が Invalid で返ってくる）。
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Build/Build/Products/Release/MenuBar Tidy.app"
XPC="$APP/Contents/XPCServices/MenuBarItemService.xpc"

xcodebuild -project Thaw.xcodeproj -scheme Thaw -configuration Release \
    -derivedDataPath Build build >/dev/null

fail=0
for target in "$XPC" "$APP"; do
    info=$(codesign -dvv "$target" 2>&1)
    case "$info" in
        *"Signature=adhoc"*) echo "NG: adhoc 署名が残存: $target"; fail=1 ;;
    esac
    case "$info" in
        *"Developer ID Application: Tsubasa Namatame"*) ;;
        *) echo "NG: Developer ID 署名でない: $target"; fail=1 ;;
    esac
    case "$info" in
        *"Timestamp="*) ;;
        *) echo "NG: secure timestamp なし: $target"; fail=1 ;;
    esac
    case "$info" in
        *"flags=0x10000(runtime)"*) ;;
        *) echo "NG: Hardened Runtime が無効: $target"; fail=1 ;;
    esac
done

ent=$(codesign -d --entitlements - "$APP" 2>&1)
case "$ent" in
    *get-task-allow*) echo "NG: get-task-allow が残存（配布で禁止）"; fail=1 ;;
esac

codesign --verify --deep --strict "$APP" || fail=1
[ "$fail" -eq 0 ] || exit 1

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p dist
ZIP="dist/MenuBarTidy-$VERSION.zip"
/bin/rm -f "$ZIP" 2>/dev/null || true
# zip -r は symlink を実体に潰して署名を壊すので ditto を使う。
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "OK: $ZIP"
echo "次: scripts/notarize.sh"
