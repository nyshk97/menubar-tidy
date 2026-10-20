# 動作確認手順

MenuBar Tidy 2.x（メニューバーの全項目を一覧に出し、選ぶとAXPressで開く）の確認手順。
変更内容に関係する項目だけ実行すればよい。全部を毎回やる必要はない。

以下のコマンドは`.mise.toml`のタスクにまとめてある（`mise tasks`で一覧）。

---

## 0. 前提

- macOS 26以上 / Xcode 26以上（`MACOSX_DEPLOYMENT_TARGET = 26.0`）
- **権限はアクセシビリティだけ**。画面収録は2.0から使わない（1.xで付けた許可は消してよい）
- 署名は自分のTeam（`VYDUR99LAM`）。ad-hocにするとTCCの許可がビルドのたびに失効する
- **Debug = dev版 / Release = 常用版**で、名前・バンドルID・アイコンが別アプリとして分かれている

  | | dev版（Debug） | 常用版（Release） |
  | --- | --- | --- |
  | バンドル | `MenuBarTidy-dev.app` | `MenuBar Tidy.app` |
  | バンドルID | `com.nyshk97.MenuBarTidy.dev` | `com.nyshk97.MenuBarTidy` |
  | アイコン | 青 + **DEVリボン**（`AppIconDev.icon`） | 青（`AppIcon.icon`） |
  | ログ（統合ログのsubsystem） | `com.nyshk97.MenuBarTidy.dev` | `com.nyshk97.MenuBarTidy` |

  - 切り替えは`project.pbxproj`のDebug構成（`PRODUCT_NAME` / `PRODUCT_BUNDLE_IDENTIFIER` /
    `ASSETCATALOG_COMPILER_APPICON_NAME`）だけ。`AppIdentity`（`Thaw/Utilities/AppIdentity.swift`）が
    実行時にバンドルIDからdev版かを判定する。ズレは`AppIdentityTests`が落として知らせる
  - **dev版はTCCの許可を別に取る**（初回起動時にアクセシビリティを付ける）
  - **常用版とdev版を同時に起動してよい**。項目を動かさないので取り合わない（1.xまでは禁止だった）。
    一覧には互いのアイコンも載る
  - Swiftのモジュール名は`Thaw`のまま（`PRODUCT_MODULE_NAME`で固定）。テストの`@testable import Thaw`が依存している
- **会社貸与PC（`TsubasanoMacBook-Pro`）では、Claude Codeのセッションから署名を伴うコマンドを叩かない**
  （署名鍵がキーチェーンにあり、EDRが「AIエージェントが認証情報ストアを参照した」を検知する）。
  セッションが自分で回せるのは次のもの。dev版の起動（`mise run run`）とリリースは自分のターミナルで叩く

  | コマンド | 何を確かめるか | 署名 |
  | --- | --- | --- |
  | `mise run test` | 単体テスト | しない |
  | `mise run check` | 整形・lint・入力リスト | しない |
  | `mise run preview` | 一覧メニューに並ぶ中身（本体のソースをそのまま組み込む） | しない |
  | `mise run items` / `swift scripts/press-ax-item.swift` | 項目の座標・押したときに開く位置 | しない |
  | `xcodebuild … CODE_SIGNING_ALLOWED=NO build` | コンパイルが通るか | しない |

### 開発機を移したとき

リポジトリに入っているのはビルド設定まで。**署名証明書・notarizeの資格情報・`gh`の
認証はkeychainにあり、リポジトリを持ち出しても付いてこない**。新しいMacでは:

```sh
mise install     # swiftformat / swiftlint を .mise.toml のバージョンで入れる
mise run doctor  # Xcode・証明書・notarize プロファイル・gh の過不足を一覧する
```

- Xcode → Settings → Accountsでサインインすると、`Apple Development`（Debug用）と
  `Developer ID Application`（Release用）の証明書が降りてくる
- notarizeの資格情報はリリースするときだけ必要（`mise run release`の事前確認でも見る）。
  自作Macアプリ共通のkeychainプロファイル`nyshk97-notary`を作る:

  ```sh
  xcrun notarytool store-credentials nyshk97-notary \
    --key ~/Library/CloudStorage/Dropbox/secrets/AuthKey_M4FG2B8JFX.p8 \
    --key-id M4FG2B8JFX --issuer 024fc873-10f9-49a4-8d6f-20fb5c7bd522
  ```

  中身はApp Store ConnectのAPIキー（`.p8`はDropboxの`secrets/`にある）。
  **App用パスワードは使わない**（発行時しか値が見えず、マシンを増やすたびに再発行になる）
- TCC（アクセシビリティ）はMacごとに付け直す。バンドルIDが同じでも移行されない
- Team ID・バンドルID・`nyshk97/*`のリポジトリ名は**アカウント側の値なので開発機を移しても
  変えない**（変えるとTCCの許可もcaskの導線も切れる）
- メニューバーの項目の間隔は`~/Dropbox/settings/setup-defaults.sh`が`NSStatusItemSpacing = 6`に
  詰める（反映はログアウト後）。アプリからは書き込まない

---

## 1. ビルド

```sh
mise run build     # 署名あり（Apple Development）。会社貸与PCではセッションから叩かない
xcodebuild -project Thaw.xcodeproj -scheme Thaw -configuration Debug -derivedDataPath Build CODE_SIGNING_ALLOWED=NO build   # 署名なし
```

出来上がるのは`Build/Build/Products/Debug/MenuBarTidy-dev.app`（dev版）。署名なしの成果物は
起動のたびにアクセシビリティの許可を取り直すことになるので、**コンパイルの確認にだけ使う**。

`| tail`や`| grep`に繋ぐときは`set -o pipefail`を付ける。付けないとxcodebuildの失敗が
パイプの終了コードに隠れて「成功」に見える。

---

## 2. テスト

```sh
mise run test
```

期待値: `✔ Test run with 27 tests in 7 suites passed`

- **署名なしで回す**（`CODE_SIGNING_ALLOWED=NO`。CIと同じ条件）。テストに署名は要らない
- テストホストとしてdev版が起動するが、`XCTestCase`があると`AppDelegate`は何も立ち上げない
  （状態アイコン・許可のプロンプト・ログイン項目の登録が、テストのたびに実メニューバーへ出るのを防ぐ）
- **`Executed 0 tests`は無視してよい**。XCTest側のカウントで、このプロジェクトはswift-testing (`@Test`)。
  実数は`Test run with N tests`の行に出る
- **同時に2本走らせない**。同じ`-derivedDataPath`を指す`xcodebuild test`を並行起動すると、
  2つのテストホストが成果物を奪い合い、片方が途中で打ち切られて`TEST FAILED`を返す。
  **コードの問題と見分けがつかない**。`mise run test`は先に`pgrep -x xcodebuild`を見て止まる
- 判定（`ItemVisibility`）・一覧に載せる規則・表示名・照合（`ItemRules`）・座標変換（`ScreenGeometry`）は
  `ThawTests/ItemRulesTests.swift`。数値はMacBook Pro 14"（1512×982pt、ノッチx=663〜848）と
  Studio Display（内蔵の上、`x=-502, y=-1440`）の実測値

---

## 3. メニューバーの項目を読む・押す（アプリを起動せずに）

スクリーンショットでは判断できない（Claude CodeのBashからは`screencapture`が真っ黒になる）。
座標はすべてCG座標（主画面の左上が原点、下向きが +y）。動かすターミナルにアクセシビリティの許可が要る。

```sh
mise run items                                   # 全項目の座標・持ち主・説明（scripts/list-ax-items.swift）
mise run preview                                 # 一覧メニューに並ぶ中身（区分・表示名）
mise run preview -- --press 検索                  # その表示名の項目を、一覧から選んだときと同じ経路で押す
swift scripts/press-ax-item.swift Pecha          # 押して、開いたウィンドウの位置と画面を測ってから閉じる
```

- `preview`は本体の`Thaw/Items/`を**署名なしでそのまま組み込んで**ビルドする。判定・表示名・押す処理は
  本体と同じコードが動く。違いは判定に使う画面のフォールバック（本体は自分のアイコンがある画面、
  `preview`は主画面）だけ
- `press-ax-item.swift`は開いたメニューを、**そのアプリにだけ** Escを送って閉じる（`CGEvent.postToPid`）。
  全体にEscを投げるとターミナルに届いてClaude Codeが止まる。**押すと実際にメニューが開く**ので、
  クリックだけで状態が変わる項目（録画の停止など）はソースやREADMEで挙動を確かめてから指定する

読み方:

| 観測 | 意味 |
|---|---|
| AXが返すのは1つの画面の項目だけ | **アクティブなメニューバーの画面**の項目だけが返る。CGのウィンドウ一覧には画面ごとの組がある |
| 項目のyが画面の上端より約60pt上（例: `-1499`、画面の上端は`-1440`） | その画面のメニューバーが引っ込んでいる（全画面のアプリ）。押すと降りてきて、その真下に開く |
| `(-1, 981)` | システム設定 → メニューバーで表示を許可していない項目（コントロールセンターの`trackedApplications`で`isAllowed = False`）。一覧に載せない |
| `(0, 982, 0×0)`でdisabled | コントロールセンターの空の項目。一覧に載せない |
| xが画面の左端より小さい | 画面外。押してもメニューが画面外に開く（一覧ではグレーアウト） |
| xがノッチ（`663〜848`）か前面アプリのメニューの右端より左 | 隠れているが、押せばその真下に見える形で開く |

### 何が確かめられているか（2026-10-20、macOS 26.6.2、MacBook Pro 14"）

| 項目の場所 | 押したときのメニュー |
|---|---|
| ノッチの裏（x=664〜811） | 真下（y=34）に開いて見える |
| アプリのメニューの下（x=495）・画面の左端付近（x=47） | 真下に開いて見える |
| 画面の左端より外（x=-177、1.xの仕切りで押し出したx≈-4000） | 画面外に開いて見えない |
| メニューバーが引っ込んだStudio Display（y=-1499） | バーが降りてきてy=-1409に開いた |

- 開いたメニューの位置はAXから変えられない（`AXPosition`が`settable=false`、セットしても変わらない）
- **SpotlightはAXPressに反応しない**（⌘Spaceで代わりが効く）。TodoMacも1.19.0までは反応しなかった
  （`NSApp.currentEvent`が`nil`だと何もしない作りだった）が、1.19.1で直り、パネルが開くことを確かめた（2026-10-20）
- メニュー型の項目にAXPressを送ると、メニューが閉じるまで呼び出しが戻らず、タイムアウトで
  `kAXErrorCannotComplete`（-25204）が返る。メニューは開いたまま。**失敗ではない**

---

## 4. アイコンと表示名

```sh
mise run info      # 表示名・バンドルID・署名（codesign -dvv は読み取りだけで、キーチェーンに触らない）
```

アイコンは**パス基準でキャッシュされる**ので、リビルド後に確認するときは新しいパスへコピーしてから引く:

```sh
FRESH=$(mktemp -d)
cp -R "Build/Build/Products/Debug/MenuBarTidy-dev.app" "$FRESH/check.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$FRESH/check.app"
# NSWorkspace.shared.icon(forFile:) で PNG 化して目視
```

Debugビルドは`Contents/Resources/AppIconDev.icns`を持つので、そちらを展開するほうが速い:

```sh
sips -s format png --resampleWidth 512 \
  "Build/Build/Products/Debug/MenuBarTidy-dev.app/Contents/Resources/AppIconDev.icns" --out /tmp/appicon.png
```

### メニューバーの状態アイコン

ビルド成果物の`Assets.car`から読んで、`AppDelegate.makeStatusIcon()`と同じリサイズを通した絵を書き出す
（アプリを起動しなくてよい）:

```sh
swift scripts/render-status-icons.swift "Build/Build/Products/Debug/MenuBarTidy-dev.app" /tmp/icons
```

- 出力の`ratio`は**1.0が正**。アセット`TidyBarFill`は34x34px @2x = 17x17ptで作ってあり、
  `max(幅/25, 高さ/17)`がちょうど1.0になってリサンプリングが起きない

---

## 5. 一覧メニュー（実機確認）

アプリのメニューそのもの（区分の見出し・グレーアウト・アイコン・押したあとの開き方）は、
dev版を起動して目で見るしかない。**会社貸与PCでは自分のターミナルで**起動する:

```sh
mise run run                       # kill → build（署名あり）→ open（dev 版）
mise run kill                      # dev 版を止める
mise run logs                      # dev 版の統合ログを追う
```

初回はアクセシビリティを許可する（未許可のあいだ、メニューには「アクセシビリティを許可…」だけが出る）。

| # | 確認項目 | 期待 |
|---|---|---|
| 1 | 自分のアイコン | 山括弧＋点2つが1個。1.xのときの位置（`NSStatusItem Preferred Position Thaw.ControlItem.Visible`）にいる |
| 2 | 一覧の区分 | 「隠れている」にノッチの裏・前面アプリのメニューの下・画面外の項目、「見えている」にそれ以外。項目が無い区分は見出しごと出ない |
| 3 | 画面外の項目 | グレーアウトして「画面外のため開けません」 |
| 4 | **隠れている項目を選ぶ** | その項目自身の位置（ノッチの裏にいるならノッチの真下）に開く。**一覧を出したアイコンの下には開かない**（macOSの決まりで、開いた位置はAXから動かせない。2026-10-20に確認し、このままとした） |
| 5 | 前面アプリを変える | メニューの多いアプリ（スクリプトエディタ等）が前面のとき、左端寄りの項目が「隠れている」に移る |
| 6 | 2枚のとき | 一覧を開いた画面のほうに開く。内蔵側のメニューバーで開くと内蔵側（ノッチの真下）、Studio Display側で開くとStudio Display側（2026-10-20に確認） |

`mise run preview`の出力と区分を突き合わせると、見た目と判定のずれを切り分けられる。

---

## 6. 文字列

**ローカライズは廃止した。** UIに出る文字列はSwiftのリテラルに日本語で直接書いてある。

```sh
mise run strings
```

- `macOS ...`や`dev版...`で始まる行は日本語文の中の英単語なので正常
- 除外している`systemSymbolName` / `accessibilityDescription`は**システム側の識別子**でUIに出ない

---

## 7. 既知の外部要因（アプリのバグではないもの）

**動作確認が失敗したとき、まずここを疑う。**以下はmacOSや他アプリ側の事情で、コードを直しても消えない。

### 全画面のアプリがある画面ではメニューバーが引っ込む

その画面の項目は、AXでは画面の上端より約60pt上にいる（§3）。一覧に載せる判定はこの位置も
メニューバーの帯として数える（`ScreenGeometry.menuBarBandAboveTop`）。

### 一部のシステム項目は ⌘ ドラッグで動かせない

並べ替えは自分で ⌘ ドラッグする。macOSは一部のシステム項目の移動を拒否する（ドラッグ中は
カーソルに付いてくるが、離すと元に戻る）。

### Control Centerの設定ファイルが壊れると複数アプリが同時に狂う

CodexBar 0.29.xがControl Centerの設定に不正な状態を書き込み、ドリフトを起こした事例がある。
Control Centerがホストする項目が**複数同時に**おかしくなったらこれを疑う。

```sh
killall ControlCenter
rm ~/Library/Preferences/com.apple.controlcenter.plist
rm ~/Library/Preferences/ByHost/com.apple.controlcenter*.plist
```

### ディスプレイ構成の変更直後は判定しない

モニタの抜き差し・スリープ復帰・Sidecar・KVM切り替えの直後は、解像度のちらつきや一時的な余白が出る。
数秒待ってから確認する。

### iPhoneミラーリング中は正しく測れない

iPhoneのライブアクティビティがミラーリングされている間は、メニューバーに隙間や空白が出る
macOS側の制約がある。ミラーリングを止めてから確認する。

---

## 8. リリース

配布はnotarize済みzipをGitHub Releaseに上げ、`nyshk97/homebrew-tap`の
`Casks/menubar-tidy.rb`を更新して`brew`から入れる形（新規インストール用）。
日々の更新はSparkle: 同じReleaseにEdDSA署名付きの`appcast.xml`を添付し、アプリは
`https://github.com/nyshk97/menubar-tidy/releases/latest/download/appcast.xml`を見に行く
（自動確認ON・ダウンロードはSparkleのダイアログで確認してから）。

```sh
mise run release            # patch bump。minor / major / x.y.z も指定できる
```

**リリースノートは`docs/CHANGELOG.md`の`[Unreleased]`から作る**（GitHub Releaseの本文とSparkleの
更新ダイアログの両方）。叩く前にセッションが`git log <前回タグ>..HEAD`を読んで`[Unreleased]`を埋めて
commitする（書き方はCHANGELOG冒頭）。空のまま叩くと事前チェックで止まる。`release.sh`が
`[Unreleased]` → `[x.y.z] - 日付`に切り出し、bumpと同じcommitに含める。

事前チェックの回帰確認（本物を叩かずに）: `python3 scripts/changelog.py check`が`[Unreleased]`空で
exit 1、`release` / `notes`はスクラッチにコピーしたCHANGELOGで試せる（書き方セクションのコード例にある
`## [Unreleased]`を拾わないこと＝フェンス内を無視していることまで見る）。

**Claude Codeのセッションから直接叩ける**（v1.0.6で実証。notarytoolもSparkleの署名鍵もkeychainから
読めた）。**ただし会社貸与PC（`TsubasanoMacBook-Pro`）では叩かない**（EDRがキーチェーンへの参照を検知する。
`[Unreleased]`の記入とcommitまでをセッションがやり、`mise run release`は自分のターミナルで叩く）。途中で失敗するとbump commitはtrapで巻き戻るので、失敗してもremoteは汚れない。
画面ロック中は事前チェック（`IOConsoleLocked`）で止まる。

内訳（個別にも回せる）:

| 手順 | コマンド | 何を確かめるか |
| --- | --- | --- |
| ビルド + 署名検証 + zip | `mise run release:zip` | Developer ID署名・secure timestamp・Hardened Runtime・`get-task-allow`不在 |
| notarize + staple | `mise run release:notarize` | `spctl --assess`が`Notarized Developer ID`を返すこと |
| EdDSA署名 + appcast | （`release.sh`内） | `sign_update --account menubar-tidy`の出力が`sparkle:edSignature=`を含み、`dist/appcast.xml`が`xmllint`を通ること |

- **Release構成だけDeveloper ID署名**（DebugはApple Developmentのまま）。
  `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`で`get-task-allow`の注入を止めてある
- **配布物は常用版の名前・バンドルIDで出る**（`MenuBar Tidy.app` / `com.nyshk97.MenuBarTidy`）。
  dev版の名前が混ざっていないかは`mise run release:zip`の後に`codesign -dvv`で確認できる
- notarizeの資格情報はkeychainプロファイル`nyshk97-notary`（`NOTARY_PROFILE`で変えられる）。
  無いときの作り方は §0「開発機を移したとき」を参照（App Store ConnectのAPIキーで登録する）
- **Sparkle.frameworkの中身は`make-release-zip.sh`がinside-outに再署名する**（`Downloader.xpc` →
  `Installer.xpc` → `Updater.app` → `Autoupdate` → framework → 最後に`.app`本体）。xcodebuildは
  frameworkの外側しか署名し直さず、中のXPCがadhocのまま残ってnotarizeがInvalidになる。
  本体の再署名を忘れるとFrameworks/ の変更で外側のsealが壊れ`codesign --verify --deep --strict`で落ちる
- **Sparkleの鍵はdev版とReleaseで扱いが違う**: `SUFeedURL` / `SUPublicEDKey` / `SUEnableAutomaticChecks`は
  Release構成専用の`Thaw/Resources/Info-Release.plist`にだけある（Debugは`Info.plist`。pbxprojの
  `INFOPLIST_FILE`で切り替え。`INFOPLIST_KEY_SU*`はXcodeが任意キーを受けないので使えない）。
  dev版に入れるとdevが常用版のダウンロードで置き換わるので、ビルド後に無いことを確認する:

  ```sh
  /usr/libexec/PlistBuddy -c "Print :SUFeedURL" Build/Build/Products/Debug/MenuBarTidy-dev.app/Contents/Info.plist   # → Does Not Exist
  /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "Build/Build/Products/Release/MenuBar Tidy.app/Contents/Info.plist"  # → feed URL
  ```

  加えて`UpdatesManager.isSupported`が`#if DEBUG`でfalseになり、dev版ではアップデータを起動しない（二重防御）
- EdDSAの秘密鍵はkeychainのaccount `menubar-tidy`（`mise run doctor`が見る）。バックアップは
  `~/Library/CloudStorage/Dropbox/secrets/sparkle-ed25519-menubar-tidy-private.key`、
  新しいMacでは`generate_keys --account menubar-tidy -f <そのファイル>`でimportする。
  公開鍵は`Info-Release.plist`の`SUPublicEDKey`（鍵を作り直したら必ず対で更新）
- zip化は`ditto -c -k --sequesterRsrc --keepParent`。`zip -r`はsymlinkを潰して署名を壊す
- 配布物の最終確認:

```sh
ditto -x -k dist/MenuBarTidy-<version>.zip /tmp/mbt-check
spctl --assess --type execute -vv "/tmp/mbt-check/MenuBar Tidy.app"   # → Notarized Developer ID
```

- リリース後のfeed確認:

  ```sh
  curl -sL https://github.com/nyshk97/menubar-tidy/releases/latest/download/appcast.xml | grep -E "shortVersionString|edSignature"
  ```

  `shortVersionString`が出したバージョン、`enclosure`に`sparkle:edSignature`があること
- `release.sh`はbumpを**ビルド前にローカルcommit**し、pushはnotarize後。途中で失敗するとtrapが
  そのcommitを`git reset --hard HEAD~1`で巻き戻す（remote未変更・作業ツリーは実行前に戻る）。
  commit前にビルドしていた頃は、表示されるcommitが`xxxx-dirty`になっていた（1.0.4で確認。2.0からは
  メニュー末尾のバージョン表示に出る）
- **起動時の自動確認は「前回確認から24h以上」のときだけ走る**（Sparkleの仕様）。リリース直後に
  旧版を再起動しても出ないのは正常。検証したいときは前回確認日時を戻してから起動する:

  ```sh
  defaults write com.nyshk97.MenuBarTidy SULastCheckTime -date "2026-01-01 00:00:00 +0000"
  open -g "/Applications/MenuBar Tidy.app"     # 数秒で「ソフトウェア・アップデート」ウィンドウが出る
  ```

  `SULastCheckTime`が現在時刻に更新されれば確認は走っている（ダイアログは別ディスプレイに出ることがある）
- **アプリ内更新の本番確認は「次のリリース」でしかできない**: 新版を出したら、旧版を起動したまま
  メニューの「アップデートを確認…」→ 新版のダイアログ → インストール → 再起動後にメニュー末尾の
  バージョン表示が上がっていること。Sparkleが入る前の版（≤ 1.0.3）からは`brew upgrade --cask nyshk97/tap/menubar-tidy`でしか上がれない

---

## 9. 罠

- **Claude CodeのBashからは`screencapture`が真っ黒になる**（画面収録権限がない）。
  メニューバーの目視確認はユーザーに依頼するか、§3のスクリプトで座標から判断する
- **バンドルIDを変えるとTCCの許可が失効する**。`com.nyshk97.MenuBarTidy`は1.xから変えていない
- **検証用に作った仮のステータス項目は、コントロールセンターの`trackedApplications`に記録される**
  （2026-10-20に`/private/tmp/axspike/overflow`・`spacing`が許可済みとして残った）。害はないが、
  システム設定 → メニューバーの一覧に出ていたら消してよい
- **他アプリのメニューを閉じるEscを全体に投げない**。メニューが開いていなかったとき、ターミナルに届いて
  Claude Codeの実行が止まる。`CGEvent.postToPid`でそのアプリにだけ送る（`press-ax-item.swift`がそうしている）
