#!/bin/bash
# Release ビルドを配布適格に仕上げて dist/MenuBarTidy-<version>.zip を作る
#
# Release 構成は Developer ID + --timestamp + get-task-allow なしで署名するよう
# project.pbxproj に設定してあるので、自前のバイナリ（本体）は
# ビルドの署名がそのまま使える。例外が Sparkle.framework: xcodebuild は埋め込んだ
# framework の外側しか再署名せず、中の XPC サービス・Updater.app・Autoupdate が
# adhoc 署名のまま残って notarize が Invalid で返る（keyrc で踏んだ）。ここで
# inside-out に Developer ID + timestamp で署名し直し、Frameworks/ の中身が変わって
# 壊れた本体の seal も最後に張り直す。その後で配布要件を満たしているか検証する。
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Build/Build/Products/Release/MenuBar Tidy.app"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_B="$SPARKLE/Versions/B"

# 署名 ID のハッシュはマシンごとに異なるため直書きせず、Team ID で keychain から解決する。
TEAM_ID="VYDUR99LAM"
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' "/Developer ID Application.*\\($TEAM_ID\\)/ {print \$2; exit}")
if [ -z "$IDENTITY" ]; then
    echo "NG: Developer ID Application（Team ${TEAM_ID}）の証明書が keychain にない" >&2
    exit 1
fi

xcodebuild -project Thaw.xcodeproj -scheme Thaw -configuration Release \
    -derivedDataPath Build build >/dev/null

# inside-out: ネストの深いバイナリから順に署名する。Sparkle の XPC は
# エンタイトルメントを持つため --preserve-metadata=entitlements で維持する。
SPARKLE_NESTED=(
    "$SPARKLE_B/XPCServices/Downloader.xpc"
    "$SPARKLE_B/XPCServices/Installer.xpc"
    "$SPARKLE_B/Updater.app"
    "$SPARKLE_B/Autoupdate"
    "$SPARKLE"
)
for nested in "${SPARKLE_NESTED[@]}"; do
    [ -e "$nested" ] || { echo "NG: Sparkle の構成物が見つからない: $nested"; exit 1; }
    codesign --force --options runtime --timestamp \
        --preserve-metadata=entitlements --sign "$IDENTITY" "$nested"
done
# 本体。--entitlements は渡さない（CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO なので
# get-task-allow は元々入っておらず、渡すものが無い）。
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

fail=0
for target in "${SPARKLE_NESTED[@]}" "$APP"; do
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

# Sparkle の配信先は Info-Release.plist（アプリが見に行く先）と release.sh（appcast を
# 置く先）の 2 箇所にある。ここで成果物の plist を読んで突き合わせ、乖離したビルドを
# 配布しない。FEED_URL は release.sh と同じ既定値で、環境変数で上書きできる。
FEED_URL="${FEED_URL:-https://github.com/nyshk97/menubar-tidy/releases/latest/download/appcast.xml}"
PLIST="$APP/Contents/Info.plist"
built_feed=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$PLIST" 2>/dev/null || true)
if [ "$built_feed" != "$FEED_URL" ]; then
    echo "NG: SUFeedURL が配信先と一致しない"
    echo "    plist : ${built_feed:-（無し）}"
    echo "    期待値: $FEED_URL"
    exit 1
fi
built_key=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST" 2>/dev/null || true)
case "$built_key" in
    ""|*PLACEHOLDER*) echo "NG: SUPublicEDKey が未設定: '${built_key}'"; exit 1 ;;
esac

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
mkdir -p dist
ZIP="dist/MenuBarTidy-$VERSION.zip"
/bin/rm -f "$ZIP" 2>/dev/null || true
# zip -r は symlink を実体に潰して署名を壊すので ditto を使う。
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "OK: $ZIP"
echo "次: scripts/notarize.sh"
