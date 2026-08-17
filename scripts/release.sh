#!/bin/bash
# MenuBar Tidy リリーススクリプト
# 使い方: ./scripts/release.sh [patch|minor|major|<x.y.z>]   （省略時は patch）
#
# 1. project.pbxproj の MARKETING_VERSION を bump（CURRENT_PROJECT_VERSION はタイムスタンプ）
# 2. make-release-zip.sh で Release ビルド + 配布要件の検証 + zip 化
# 3. notarize.sh で notarize + staple
# 4. バージョン更新を commit して main に push
# 5. GitHub Release（v<version>）を作成し zip を添付
# 6. nyshk97/homebrew-tap の Casks/menubar-tidy.rb を作成/更新
# 7. ローカルの tap を同期
#
# notarize（失敗しやすい工程）を push より前に置く。失敗時は pbxproj の変更が
# ローカルに残るだけで remote には何も反映されない（`git checkout` で戻せる）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="MenuBar Tidy"
BUNDLE_ID="com.nyshk97.MenuBarTidy"
TEAM_ID="VYDUR99LAM"
NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"
GITHUB_REPO="nyshk97/menubar-tidy"
TAP_REPO="nyshk97/homebrew-tap"
CASK_TOKEN="menubar-tidy"
CASK_PATH="Casks/${CASK_TOKEN}.rb"
PBXPROJ="Thaw.xcodeproj/project.pbxproj"

# ===== バージョン計算 =====
CURRENT_VERSION="$(grep -m1 'MARKETING_VERSION = ' "$PBXPROJ" | sed 's/.*MARKETING_VERSION = //' | tr -d '";' | tr -d ' ')"
echo "現在のバージョン: $CURRENT_VERSION"

BUMP="${1:-patch}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  [0-9]*.[0-9]*.[0-9]*) IFS='.' read -r MAJOR MINOR PATCH <<< "$BUMP" ;;
  *) echo "不正なバージョン指定: ${BUMP}（patch|minor|major|x.y.z）"; exit 1 ;;
esac
NEW_VERSION="$MAJOR.$MINOR.$PATCH"
BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"
TAG="v$NEW_VERSION"
DIST_ZIP="$REPO_ROOT/dist/MenuBarTidy-$NEW_VERSION.zip"
echo "新しいバージョン: $NEW_VERSION (build $BUILD_NUMBER)"

# ===== リリース前チェック =====
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ 作業ツリーに未コミットの変更があります。コミットしてから実行してください。"
  git status --short
  exit 1
fi
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "❌ リリース $TAG は既に存在します。"
  exit 1
fi

# ===== 環境の事前確認 =====
# 署名証明書も notarize の資格情報も keychain にあり、リポジトリには入らない。
# 開発機を移すとここだけが欠ける。先に見ておかないと、5〜10 分の Release ビルドを
# 終えてから notarize で落ち、bump 済みの pbxproj が中途半端に残る。
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
case "$IDENTITIES" in
  *"Developer ID Application"*"($TEAM_ID)"*) ;;
  *) echo "❌ Developer ID Application 証明書（${TEAM_ID}）が keychain にありません。"
     echo "   Xcode → Settings → Accounts → Manage Certificates から取得してください。"
     exit 1 ;;
esac
if ! NOTARY_CHECK="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>&1)"; then
  echo "❌ notarize の keychain プロファイル '$NOTARY_PROFILE' が使えません:"
  echo "$NOTARY_CHECK" | head -3
  echo "   作成: xcrun notarytool store-credentials $NOTARY_PROFILE \\"
  echo "           --apple-id <Apple ID> --team-id $TEAM_ID"
  echo "   （パスワードは appleid.apple.com で発行する App 用パスワード）"
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "❌ gh が未認証です。gh auth login を先に済ませてください。"
  exit 1
fi

# ===== バージョン更新 =====
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $NEW_VERSION;/" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/" "$PBXPROJ"

# ===== ビルド + 署名検証 + notarize（remote 反映前に実施）=====
bash "$REPO_ROOT/scripts/make-release-zip.sh"
bash "$REPO_ROOT/scripts/notarize.sh"

[ -f "$DIST_ZIP" ] || { echo "❌ 配布 zip が見つかりません: $DIST_ZIP"; exit 1; }
SHA256="$(shasum -a 256 "$DIST_ZIP" | awk '{print $1}')"

# ===== commit + push =====
git add "$PBXPROJ"
git commit -m "chore: bump version to $TAG"
git push origin main

# ===== GitHub Release =====
echo "🚀 GitHub Release を作成中..."
gh release create "$TAG" "$DIST_ZIP" \
  --repo "$GITHUB_REPO" \
  --title "$TAG" \
  --generate-notes

# ===== Cask 更新（nyshk97/homebrew-tap）=====
echo "🍺 Cask $CASK_PATH を更新中..."
CASK_CONTENT="$(cat <<CASK
cask "$CASK_TOKEN" do
  version "$NEW_VERSION"
  sha256 "$SHA256"

  url "https://github.com/$GITHUB_REPO/releases/download/v#{version}/MenuBarTidy-#{version}.zip"
  name "$APP_NAME"
  desc "メニューバー項目を隠して整理する常駐アプリ（Thaw の個人用フォーク）"
  homepage "https://github.com/$GITHUB_REPO"

  depends_on macos: :tahoe

  app "$APP_NAME.app"

  uninstall quit: "$BUNDLE_ID"

  zap trash: [
    "~/Library/Application Support/$APP_NAME",
    "~/Library/Caches/$BUNDLE_ID",
    "~/Library/Logs/$APP_NAME",
    "~/Library/Preferences/$BUNDLE_ID.plist",
  ]

  caveats <<~EOS
    起動には以下の権限が必要です
    （システム設定 → プライバシーとセキュリティ）:
      - アクセシビリティ
      - 画面収録

    アップグレード後は権限の再付与を求められることがあります。
  EOS
end
CASK
)"

ENCODED="$(printf '%s' "$CASK_CONTENT" | base64)"
EXISTING_SHA="$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.sha' 2>/dev/null || true)"
if [ -n "$EXISTING_SHA" ]; then
  gh api "repos/$TAP_REPO/contents/$CASK_PATH" \
    --method PUT \
    --field message="chore: $CASK_TOKEN $NEW_VERSION" \
    --field content="$ENCODED" \
    --field sha="$EXISTING_SHA" \
    --silent
else
  gh api "repos/$TAP_REPO/contents/$CASK_PATH" \
    --method PUT \
    --field message="feat: add $CASK_TOKEN $NEW_VERSION" \
    --field content="$ENCODED" \
    --silent
fi

# ===== ローカル tap 同期 =====
# brew のローカル tap クローンは自動更新されないので、ここで pull しておかないと
# 直後の `brew bundle` が「No available formula or cask」になる。
TAP_DIR="$(brew --repository "$TAP_REPO" 2>/dev/null || true)"
if [ -n "$TAP_DIR" ] && [ -d "$TAP_DIR/.git" ]; then
  git -C "$TAP_DIR" pull --ff-only --quiet origin main || true
fi

echo ""
echo "✅ リリース完了: $TAG"
echo "   asset : https://github.com/$GITHUB_REPO/releases/download/$TAG/MenuBarTidy-$NEW_VERSION.zip"
echo "   sha256: $SHA256"
echo "   cask  : $TAP_REPO $CASK_PATH"
