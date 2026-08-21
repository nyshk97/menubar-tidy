# Sparkle によるアプリ内アップデート

## 概要・やりたいこと

現状の配布は brew cask のみで、新版が出ても `brew upgrade` を手で叩かないと入れ替わらない。
設定画面とメニューバーのメニューから「アップデートを確認」できるようにし、起動時・定期の
自動確認で更新があればダイアログで知らせ、その場でインストールできるようにする。

自分専用 Mac アプリの型（`personal-mac-apps.md`）に合わせ、PolePole・daw・keyrc と同じく
Sparkle 2 を使う。配信形態は keyrc 型（ソース repo の GitHub Release に `appcast.xml` を固定名で添付）。

## 前提・わかっていること

### 決定事項（/dig）
| 論点 | 決定 |
|---|---|
| 方式 | Sparkle 2（SPM）。上流 Thaw が削り込み最初のコミット `5a2b25eb` で削除した `Thaw/Main/Updates.swift`（`UpdatesManager`）を復元ベースにし、feed URL・公開鍵を差し替える |
| 配信 | `release.sh` で EdDSA 署名 → `appcast.xml` 生成 → zip と一緒に GitHub Release に添付。`SUFeedURL = https://github.com/nyshk97/menubar-tidy/releases/latest/download/appcast.xml` |
| UI（設定画面） | 下部のバージョン行（`MenuBar Tidy 1.0.3 (…)`）の横に「アップデートを確認」ボタンだけ。カード追加・トグル無し |
| UI（メニュー） | 「アップデートを確認…」を常に表示（「MenuBar Tidy 設定…」の下） |
| 自動更新 | 自動確認 ON（`SUEnableAutomaticChecks=true` で初回の同意ダイアログを出さない）。DL は Sparkle のダイアログで確認してから。**`personal-mac-apps.md` は手動のみを推奨しているが、/dig で意図的に違えた**（自分専用で更新の取りこぼしを無くしたい） |
| 署名鍵 | このアプリ専用に新規作成（keychain account `menubar-tidy`）。秘密鍵は `~/Library/CloudStorage/Dropbox/secrets/sparkle-ed25519-menubar-tidy-private.key` にバックアップ |
| リリースノート | `<sparkle:fullReleaseNotesLink>` で GitHub Release ページへリンク（ダイアログには「リリースノートを見る」リンクだけ出てブラウザで開く。`releaseNotesLink` だとダイアログ内 WKWebView に GitHub のフルページが出て見栄えが悪い）。`gh release create --generate-notes` は維持 |
| brew | cask 維持（新規インストール用）。`release.sh` の cask 更新もそのまま。brew 側の記録が古くなるのは `brew upgrade` 時に上書きされるだけで実害なし |
| dev 版 | 二重防御: ① `SUFeedURL` / `SUPublicEDKey` / `SUEnableAutomaticChecks` は pbxproj の **Release 構成にだけ** `INFOPLIST_KEY_*` で置き、dev 版は構造的に更新先を持たない ② `#if DEBUG` でアップデータを起動しない。ボタン/メニューは無効化し「dev 版では使えません」 |
| 検証 | v1.0.4 で搭載して「最新です」まで確認 → v1.0.5（小変更）でアプリ内更新を実環境で確認 |

### 調査で確定したこと
- 上流の `5a2b25eb^:Thaw/Main/Updates.swift`（235 行）に `SPUStandardUpdaterController` の組み立て・
  `SPUUpdaterDelegate` / `SPUStandardUserDriverDelegate` 実装・`#if DEBUG` ガード付き `checkForUpdates()` が
  そろっている。`UpdateConsentSheet` / `UserNotificationManager` / beta チャンネル / 自動DLトグルは今回不要
- `Thaw.xcodeproj` は XcodeGen ではなく pbxproj 直編集。Sparkle の SPM 参照も `5a2b25eb` の差分から復元できる
- `GENERATE_INFOPLIST_FILE = YES` なので、Sparkle のキーは `Thaw/Resources/Info.plist` に直書きせず pbxproj の
  Release 構成に `INFOPLIST_KEY_SUFeedURL` 等として置く（Debug 構成には置かない）。生成後の plist に入るかは
  `PlistBuddy -c "Print :SUFeedURL"` で確認する
- 上流の `Updates.swift` は **gentle reminder 契約**（`supportsGentleScheduledUpdateReminders = true` +
  `standardUserDriverShouldHandleShowingScheduledUpdate` がアプリ非アクティブなら `false`）で、Sparkle はダイアログを
  出さずアプリ側が UserNotification で知らせる設計。LSUIElement アプリはほぼ常に非アクティブなので、UserNotification
  連携だけ削ると**自動確認で更新を見つけても無言で終わる**。gentle reminder 系のデリゲートごと削って Sparkle 標準の
  アラートに任せる
- `Package.resolved`（`Thaw.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`）は追跡されており `5a2b25eb` で
  変更されている。pbxproj と一緒に復元対象
- `generate_keys` / `sign_update` は SPM artifact なので、フルビルドを待たず
  `xcodebuild -resolvePackageDependencies -project Thaw.xcodeproj -scheme Thaw -derivedDataPath Build` で先に落とせる
- `.gitignore:19` の `plans/`（上流由来）が `docs/plans/` にも効いていて、この plan は現状追跡されない
- `CFBundleVersion` はリリース時刻のタイムスタンプ（例 `20260821213534`）。単調増加なので Sparkle の新旧比較にそのまま使える
- sandbox 無し（entitlements ファイル自体が無い）。Sparkle の XPC 構成は不要
- `scripts/make-release-zip.sh` は署名の**検証のみ**で再署名をしていない。keyrc で踏んだ「xcodebuild は埋め込んだ
  Sparkle.framework の外側しか再署名せず notarize が落ちる」対策として、`Downloader.xpc` / `Installer.xpc` /
  `Updater.app` / `Autoupdate` / framework 本体の Developer ID 再署名（`--preserve-metadata=entitlements`）を
  内側から順に足す必要がある（`~/keyrc/scripts/make-release-zip.sh` が手本）
- `sign_update` は SPM の artifacts に落ちる: `Build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update`
  （`-derivedDataPath Build` 前提。`generate_keys` も同じ場所）
- `release.sh` は「自分の Terminal で実行」（Claude Code の Bash からは notarytool が keychain に届かない）。
  Sparkle の署名鍵も keychain なので同じ制約
- 参考実装: `~/keyrc/scripts/publish-release.sh`（appcast 生成）、`~/keyrc/Sources/AppDelegate.swift`
  （`SPUStandardUpdaterController` の最小構成）、`~/daw/scripts/release.sh`（`--account` 付き署名）

## 実装計画

### Phase 0: 下ごしらえ [AI🤖]
- [x] `.gitignore` に `!docs/plans/` を足して plan を追跡対象にする（上流の `plans/` は残す）
- [x] `xcodebuild -resolvePackageDependencies … -derivedDataPath Build` で Sparkle の artifact を先に落とし、
      `Build/SourcePackages/artifacts/sparkle/Sparkle/bin/{generate_keys,sign_update}` があることを確認
      （Phase 1 のコード復元と「Phase 1前の準備」の鍵生成を並行できる）

### Phase 1前の準備 [人間👨‍💻]
**自分の Terminal で**（keychain 操作のため）:
- [x] Dropbox が秘密鍵を git に拾わないことを先に確認（AI 側で確認済み: `secrets/*` が ignore）:
      `git -C ~/Library/CloudStorage/Dropbox check-ignore -v secrets/sparkle-ed25519-menubar-tidy-private.key`
      （何も出なければ `secrets/` を ignore に足してから進む）
- [x] 専用鍵を作る: `Build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account menubar-tidy`
      → 出力された**公開鍵**を AI に渡す（`INFOPLIST_KEY_SUPublicEDKey` に入れる）
- [x] 秘密鍵をバックアップ: `… /generate_keys --account menubar-tidy -x ~/Library/CloudStorage/Dropbox/secrets/sparkle-ed25519-menubar-tidy-private.key`
      （新しい Mac では `generate_keys --account menubar-tidy -f <file>` で import）

### Phase 1: Sparkle の組み込みと UpdatesManager の復元 [AI🤖]
- [x] `project.pbxproj` と `Package.resolved` に Sparkle の SPM 参照と product 依存を復元（`git show 5a2b25eb` の逆適用を手本に。`from: 2.6.0`）
- [x] ~~pbxproj の **Release 構成にだけ** `INFOPLIST_KEY_SU*` を置く~~ → Release 専用 `Info-Release.plist` に変更（ログ参照）。公開鍵 `OVgig…QVY=` を反映済み
- [x] `Thaw/Main/Updates.swift` を `5a2b25eb^` から復元し、以下を**削る**:
  - beta チャンネル（`allowsBetaUpdates` / `allowedChannels(for:)`）
  - `automaticallyDownloadsUpdates` / `automaticallyChecksForUpdates` の公開プロパティ
  - UserNotification 連携・同意シート関連（`updaterShouldPromptForPermissionToCheck` は `false` 固定で残してよい）
  - **gentle reminder 系**: `supportsGentleScheduledUpdateReminders` / `standardUserDriverShouldHandleShowingScheduledUpdate` /
    `standardUserDriverWillHandleShowingUpdate` / `standardUserDriverDidReceiveUserAttention` / `updater(_:willScheduleUpdateCheckAfterDelay:)`
    （Sparkle 標準のアラートに任せる。残すと LSUIElement アプリでは自動確認が無言で終わる）
- [x] `AppState` に `updatesManager` を戻し `performSetup` → `startUpdaterIfNeeded()`（`#if DEBUG` では起動しない）
- [x] 文言は日本語直書き（`mise run strings` が英語の紛れ込みを検出する）
- [x] `mise run lint:inputs` で xcfilelist を再生成（新規ファイル追加時。CI の `lint:inputs:verify` が落ちる）
- [x] `mise run build` が通り、dev 版の生成 plist に `SUFeedURL` が**無い**こと:
      `/usr/libexec/PlistBuddy -c "Print :SUFeedURL" Build/Build/Products/Debug/MenuBarTidy-dev.app/Contents/Info.plist` が `Does Not Exist` で落ちる

### Phase 2: UI [AI🤖]
- [x] `MenuBarLayoutSettingsPane` の footer（バージョン行、`MenuBarLayoutSettingsPane.swift:228` 付近）に
      「アップデートを確認」ボタンを追加。`canCheckForUpdates` で無効化。dev 版は無効＋ help「dev 版では使えません」
- [x] `ControlItem` のメニュー（`ControlItem.swift:844` 付近）に「アップデートを確認…」を「MenuBar Tidy 設定…」の直後に追加。
      dev 版は disabled
- [x] `mise run check` / `mise run test` が通ること。`AppIdentityTests` 等に影響がないこと
- [x] Release ビルド（`mise run release:zip` のビルド部分）の plist に `SUFeedURL` / `SUPublicEDKey` / `SUEnableAutomaticChecks` が入っている

### Phase 3: リリースパイプライン [AI🤖]
- [x] `scripts/make-release-zip.sh`: Sparkle 埋め込み物の Developer ID 再署名を追加（内側から: `Downloader.xpc` → `Installer.xpc` →
      `Updater.app` → `Autoupdate` → `Sparkle.framework` → **最後に `.app` 本体**）。Frameworks/ の中身が変わると外側の seal が
      壊れ、既存の `codesign --verify --deep --strict`（:41）で落ちるため。本体は `codesign --force --options runtime --timestamp
      --sign "Developer ID Application…"` で、`--entitlements` は渡さない（`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` なので
      `get-task-allow` は元々入らない）。XPC は `--preserve-metadata=entitlements`。冒頭の「ここでの再署名は不要」コメントも書き換える。
      既存の検証（secure timestamp / Hardened Runtime / `get-task-allow` 不在）は Sparkle 側にも掛け、
      **`sign_update` の存在はこのスクリプトの後で assert する**
- [x] `scripts/release.sh`:
  - ビルド前の事前チェックには **keychain の鍵存在だけ**を足す
    （`security find-generic-password -s https://sparkle-project.org -a menubar-tidy`）。`sign_update` は
    `Build/SourcePackages/artifacts/` にビルド（パッケージ解決）で落ちるので、ビルド前に見ると `mise run clean` 後や
    新しい Mac で偽 fail する → `make-release-zip.sh` の後で存在を assert
  - notarize 後に `sign_update --account menubar-tidy "$DIST_ZIP"` → `dist/appcast.xml` を生成
    （`sparkle:version` = `$BUILD_NUMBER`、`sparkle:shortVersionString` = `$NEW_VERSION`、`minimumSystemVersion` = 26.0、
    `<sparkle:fullReleaseNotesLink>` = Release ページ URL、`enclosure url` = `releases/download/v$NEW_VERSION/MenuBarTidy-$NEW_VERSION.zip`）
  - `gh release create` に `dist/appcast.xml` を添付（asset 名は**実ファイル名**で決まるので `appcast.xml` のまま）
  - appcast は累積不要（`releases/latest/download/appcast.xml` は常に最新 Release の物を指す。1 item で足りる）
- [x] `mise run doctor` に Sparkle 鍵の有無を追加
- [x] `.gitignore` に `dist/appcast.xml` が入ること（`dist/` 全体が既に無視されているなら不要）
- [x] `VERIFY.md` §8 を更新: appcast の確認手順、Sparkle 側の `spctl` / `codesign --verify --deep` の見方、
      「初回搭載版では更新は降ってこない（次のリリースで検証）」の注記

### リリース v1.0.4 [人間👨‍💻]
- [x] `mise run release`（自分の Terminal）
- [x] `brew upgrade --cask nyshk97/tap/menubar-tidy` で入れ替え（Sparkle 無しの 1.0.3 からは brew でしか上がれない）
- [x] 設定画面の「アップデートを確認」→「最新バージョンです」が出る
- [ ] メニューの「アップデートを確認…」でも同じ（未確認。1.0.5 で併せて見る）
- [x] `curl -sL https://github.com/nyshk97/menubar-tidy/releases/latest/download/appcast.xml` で item が 1.0.4 を指している
- [x] ログ（`~/Library/Logs/MenuBar Tidy/`）に Sparkle 起動のエラーが無い

### リリース v1.0.5 で本番検証 [人間👨‍💻 + AI🤖]
- [ ] 小さな変更（VERIFY.md の追記など）で `mise run release`
- [ ] 1.0.4 を起動したまま「アップデートを確認」→ 1.0.5 のダイアログ → インストール → 再起動後に `ver 1.0.5`
- [ ] 起動時の自動確認でもダイアログが出る（1.0.4 を入れ直して起動すれば再現できる）
- [ ] 結果を VERIFY.md §8 に反映

## ログ
### 試したこと・わかったこと
- 2026-08-21: 上流が使っていた Sparkle は 2.9.5（`from: 2.9.5` → 解決 2.9.6）。plan の `from: 2.6.0` は keyrc の値で、上流に合わせた
- 2026-08-21: v1.0.4 リリース。Sparkle 起動（`SUHasLaunchedBefore` / `SULastCheckTime` が書かれる）、手動確認で
  「最新版を使用しています！」。フッターの commit が `33ef29b4-dirty` だった → release.sh が commit 前にビルドしていたため。
  bump をビルド前にローカル commit し、失敗時は trap で巻き戻す形に変更（1.0.5 の変更内容）
- 2026-08-21: `INFOPLIST_KEY_SUFeedURL` 等は **生成 plist に入らない**（Xcode は既知のキーしか `INFOPLIST_KEY_*` で受けない。
  Release ビルドして PlistBuddy で確認して判明）。Release 構成だけ `INFOPLIST_FILE = Thaw/Resources/Info-Release.plist` に
  切り替える方式に変更。dev 版に無い・Release に有るを両方 PlistBuddy で確認

### 方針変更
- Release 限定の Sparkle キーは `INFOPLIST_KEY_*`（pbxproj）ではなく、Release 専用の `Info-Release.plist` で持つ（上記の理由）
