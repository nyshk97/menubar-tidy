# 動作確認手順

`thaw-app/Thaw` のフォークを最小構成に削り込む作業（`INVESTIGATION.md` 参照）用の確認手順。
変更内容に関係する項目だけ実行すればよい。全部を毎回やる必要はない。

以下のコマンドは `.mise.toml` のタスクにまとめてある（`mise tasks` で一覧）。
`mise run test` はテスト後の後始末（§2）を自動で行う。

---

## 0. 前提

- macOS 26 以上 / Xcode 26 以上（`MACOSX_DEPLOYMENT_TARGET = 26.0`）
- 署名は自分の Team（`VYDUR99LAM`）。ad-hoc にすると TCC の許可がビルドのたびに失効する
- **Debug = dev 版 / Release = 常用版**で、名前・バンドルID・アイコン・データの置き場が別アプリとして分かれている。
  常用版（brew で入れたもの）を動かしたまま dev 版をビルド・クラッシュさせられる

  | | dev 版（Debug） | 常用版（Release） |
  | --- | --- | --- |
  | バンドル | `MenuBarTidy-dev.app` | `MenuBar Tidy.app` |
  | バンドルID | `com.nyshk97.MenuBarTidy.dev` | `com.nyshk97.MenuBarTidy` |
  | アイコン | 青 + **DEV リボン**（`AppIconDev.icon`） | 青（`AppIcon.icon`） |
  | ログ | `~/Library/Logs/MenuBarTidy-dev/` | `~/Library/Logs/MenuBar Tidy/` |
  | プロファイル | `~/Library/Application Support/MenuBarTidy-dev/Profiles/` | 同 `MenuBar Tidy/Profiles/` |
  | 画像キャッシュ | `~/Library/Caches/com.nyshk97.MenuBarTidy.dev/` | `~/Library/Caches/com.nyshk97.MenuBarTidy/` |

  - 切り替えは `project.pbxproj` の Debug 構成（`PRODUCT_NAME` / `PRODUCT_BUNDLE_IDENTIFIER` /
    `ASSETCATALOG_COMPILER_APPICON_NAME`）だけ。パスとサービス名は実行時に
    `AppIdentity`（`Shared/Utilities/AppIdentity.swift`）がバンドルIDから導く。
    ズレは `AppIdentityTests` が落として知らせる
  - **dev 版は TCC の許可を別に取る**（初回起動時にアクセシビリティと画面収録を付け直す）。
    バンドルIDを変えると許可が失効するのは常用版も同じ（`tccutil reset` して付け直す）
  - **両方を同時に起動しない**。同じメニューバーを奪い合う（本家 Thaw との関係と同じ）
  - Swift のモジュール名は `Thaw` のまま（`PRODUCT_MODULE_NAME` で固定）。テスト全 154 ファイルの
    `@testable import Thaw` がこれに依存している
  - 本家 Thaw（`com.stonerl.Thaw` / **アンバー**アイコン）は**アンインストール済み**。
    入れ直すと同じメニューバーを奪い合うので、両方を同時に起動しないこと

### 開発機を移したとき

リポジトリに入っているのはビルド設定まで。**署名証明書・notarize の資格情報・`gh` の
認証は keychain にあり、リポジトリを持ち出しても付いてこない**。新しい Mac では:

```sh
mise install     # swiftformat / swiftlint を .mise.toml のバージョンで入れる
mise run doctor  # Xcode・証明書・notarize プロファイル・gh の過不足を一覧する
```

- Xcode → Settings → Accounts でサインインすると、`Apple Development`（Debug 用）と
  `Developer ID Application`（Release 用）の証明書が降りてくる
- notarize の資格情報はリリースするときだけ必要（`mise run release` の事前確認でも見る）。
  自作 Mac アプリ共通の keychain プロファイル `nyshk97-notary` を作る:

  ```sh
  xcrun notarytool store-credentials nyshk97-notary \
    --key ~/Library/CloudStorage/Dropbox/secrets/AuthKey_M4FG2B8JFX.p8 \
    --key-id M4FG2B8JFX --issuer 024fc873-10f9-49a4-8d6f-20fb5c7bd522
  ```

  中身は App Store Connect の API キー（`.p8` は Dropbox の `secrets/` にある）。
  **App 用パスワードは使わない**（発行時しか値が見えず、マシンを増やすたびに再発行になる）
- TCC（アクセシビリティ・画面収録）は Mac ごとに付け直す。バンドルIDが同じでも移行されない
- Team ID・バンドルID・`nyshk97/*` のリポジトリ名は**アカウント側の値なので開発機を移しても
  変えない**（変えると TCC の許可も cask の導線も切れる）

---

## 1. ビルド

```sh
xcodebuild -project Thaw.xcodeproj -scheme Thaw -configuration Debug -derivedDataPath Build build
```

出来上がるのは `Build/Build/Products/Debug/MenuBarTidy-dev.app`（dev 版）。常用版と同じ
`MenuBar Tidy.app` が欲しいときは `-configuration Release`（`mise run release:zip`）。

`| tail` や `| grep` に繋ぐときは `set -o pipefail` を付ける。付けないと xcodebuild の失敗が
パイプの終了コードに隠れて「成功」に見える。

---

## 2. テスト

```sh
set -o pipefail
xcodebuild -project Thaw.xcodeproj -scheme Thaw -configuration Debug -derivedDataPath Build test 2>&1 \
  | grep -E "✘|error:|Test run with|TEST (SUCCEEDED|FAILED)"
```

期待値: `✔ Test run with 1741 tests in 218 suites passed`（削り込みで件数は減り続ける）

- **`Executed 0 tests` は無視してよい**。XCTest 側のカウントで、このプロジェクトは swift-testing (`@Test`)。
  実数は `Test run with N tests` の行に出る
- 落ちたテストが自分の変更由来か疑わしいときは `git stash` してベースコミットで同じテストを回す
- **同時に2本走らせない**。同じ `-derivedDataPath` を指す `xcodebuild test` を並行起動すると、
  2つのテストホストがビルド成果物と UserDefaults ドメインを奪い合い、片方が途中で打ち切られて
  `TEST FAILED` を返す（実例: 2235 tests のはずが 782 tests で終了）。**コードの問題と見分けが
  つかない**。実行前に `pgrep -x xcodebuild` が何も出さないことを確認する（macOS の `pgrep` に
  `-c` は無い）。件数が想定と違ったら並行実行を疑う
- **ローカルでは `-destination 'platform=macOS'` を付けない**。付けると対象が一部（557 件）に
  絞られたうえ `TEST FAILED` になる。CI がこれを付けているのは runner 側の事情

### ⚠ テストの後始末（必須）

**`xcodebuild test` はアプリの実 UserDefaults ドメインを壊し、テストホストのアプリを常駐させる。**

`Defaults.store`（`Thaw/Utilities/Defaults.swift`）は単一のグローバル変数で、テストはこれを
スクラッチ領域に差し替える。しかし swift-testing はスイートを並列実行し、さらに実アプリが
テストホストとして同一プロセスで動くため、差し替えの隙間に書き込みが実ドメインへ落ちる。
（このリスクは `Defaults.swift` のコメント自身が "not safe once tests run in parallel" と認めている）

実害の例: `ShowIceIcon=0` になり自アプリのアイコンが幅1に潰れる。`ShowOnClick=0` になり
空欄クリックが効かなくなる。**アプリのバグと見分けがつかない。**

```sh
# 1. 常駐したテストホストを止める（放置するとユーザーのメニューバーを操作し続ける）
pkill -f "$PWD/Build/.*MenuBarTidy-dev"

# 2. 汚染を検出（既定 false なので 1 なら汚染）
defaults read com.nyshk97.MenuBarTidy.dev ShowOnHover

# 3. 汚染していたら退避して削除
defaults export com.nyshk97.MenuBarTidy.dev /tmp/thaw-domain-backup.plist
defaults delete com.nyshk97.MenuBarTidy.dev
```

---

## 3. メニューバーの状態を読む

スクリーンショットでは判断できない。**押し出された項目は負の X 座標のウィンドウとして存在し、
macOS が受理したが描画していない項目は幅1のウィンドウとして存在する**。どちらも見た目は
「アイコンが消えた」と同じになる。

```sh
swift scripts/list-menu-bar-items.swift
```

読み方:

| 観測 | 意味 |
|---|---|
| `Thaw.ControlItem.Hidden` が幅 ~5016 で、その左が全部負のX | 押し出しが正常動作 |
| `Thaw.ControlItem.Visible` が幅 **33** | 自アプリのアイコンが描画されている |
| `Thaw.ControlItem.Visible` が幅 **1** | `hideIceIconCompletely()` が走った ＝ `ShowIceIcon` が false |
| 同名の control item が2つ | `recreateStatusItem` の過渡状態。数秒待って撮り直す |

### ログイン項目の登録状態

常用版だけが登録され、dev 版は登録されていない（または解除済み）ことの確認。
`sfltool dumpbtm` は管理者パスワードのプロンプトで止まるので、BTM の DB を直接読む:

```sh
python3 - <<'PY'
import plistlib
d=plistlib.load(open('/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v16.btm','rb'))
o=d['$objects']
for x in o:
    if isinstance(x,dict) and 'MenuBarTidy' in str(x.get('bundleIdentifier','')):
        print(x['bundleIdentifier'], 'disposition=', x['disposition'])
PY
```

`disposition` は bit0 が enabled。常用版 `11`（有効）、dev 版 `10` or 記録なし が正。
dev 版が `11` なら古いビルドが登録している ＝ 再起動で二重起動してメニューバーが消える。
現在の dev 版は起動時に自分の登録を解除するので、`mise run run` で直る。


---

## 4. アイコンと表示名

```sh
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "Build/Build/Products/Debug/MenuBarTidy-dev.app/Contents/Info.plist"
codesign -dvv "Build/Build/Products/Debug/MenuBarTidy-dev.app" 2>&1 | grep -E "Identifier|TeamIdentifier"
```

アイコンは**パス基準でキャッシュされる**ので、リビルド後に確認するときは新しいパスへコピーしてから引く:

```sh
FRESH=$(mktemp -d)
cp -R "Build/Build/Products/Debug/MenuBarTidy-dev.app" "$FRESH/check.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$FRESH/check.app"
# NSWorkspace.shared.icon(forFile:) で PNG 化して目視
```

Debug ビルドは `Contents/Resources/AppIconDev.icns` を持つので、そちらを展開するほうが速い:

```sh
sips -s format png --resampleWidth 512 \
  "Build/Build/Products/Debug/MenuBarTidy-dev.app/Contents/Resources/AppIconDev.icns" --out /tmp/appicon.png
```

### メニューバーの状態アイコン

**アプリを起動して目視しない。** 権限が要るうえ、実メニューバーを掴んで作業中の環境を壊す。
ビルド成果物の `Assets.car` から読んで、`ControlItemImage.catalog` と同じリサイズを通した絵を書き出す:

```sh
swift scripts/render-status-icons.swift "Build/Build/Products/Debug/MenuBarTidy-dev.app" /tmp/icons
```

- 出力の `ratio` は **1.0 が正**。アセットは 34x34px @2x = 17x17pt で作ってあり、
  `max(幅/25, 高さ/17)` がちょうど 1.0 になってリサンプリングが起きない
  （40x40 で作ると 40→34 の縮小が入って輪郭が甘くなる）
- カタログに入ったかどうかだけなら `assetutil` で足りる:

```sh
xcrun --sdk macosx assetutil --info \
  "Build/Build/Products/Debug/MenuBarTidy-dev.app/Contents/Resources/Assets.car" \
  | grep -A2 TidyBar
```

グリフの大きさは実機のメニューバーを実測して合わせる（現状: Bluetooth 8.5x14.5pt /
Wi-Fi 17x12.5pt / バッテリー 16x12pt に対して TidyBar は 14.7x11pt）。

---

## 5. 5つの中核機能（実機確認）

自動化できない。**権限付与は System Settings の手動操作が必須**で、合成クリックでの検証は
ユーザーの実メニューバーを壊すリスクがある。

起動と片付けは mise タスクで済む。**常用版と同時に動かさない**ので、先に常用版を止める:

```sh
osascript -e 'tell application "MenuBar Tidy" to quit'  # 常用版（/Applications）を止める
mise run run                                            # kill → build → open（dev 版）
mise run kill && open -a "MenuBar Tidy"                 # dev 版を止めて常用版に戻す
```

`mise run kill` は `$APP` の**絶対パス**で pkill する。アプリ名を決め打ちすると
`PRODUCT_NAME` を変えた後に何も止まらないのに成功して見える（dev 版へのリネーム後に
実際に起き、dev と常用版の同時起動になった）。止まったかは `pgrep -lf MenuBarTidy-dev`
で確かめる（何も出ないのが正）。

初回は アクセシビリティ と 画面収録 の両方を許可する。**どちらも必須**で、片方でも欠けると
権限画面が出て「続ける」が押せない（§7 の検証手順を参照）。

| # | 確認項目 | 期待 |
|---|---|---|
| 1 | 自アプリのアイコン | Control Center の左にシェブロン＋ドット2つが1個 |
| 2 | 押し出し | 仕切りより左の項目がメニューバーから消える |
| 3 | 空欄クリック | ThawBar（独立バー）が出る |
| 4 | **ThawBar 上のクリック転送** | アイコンを押すとそのアプリのメニューが開く |
| 5 | 仕切り位置の永続化 | 再起動しても位置が保たれる |

4 が最重要。`MenuBarItemManager.click(item:with:)`（AX → 合成CGEvent の2段）と
`temporarilyShow(...)`（実バーへ移動→クリック→復帰）の両経路がここに集約されている。

本家 Thaw を入れ直した場合は、**両者が同じメニューバーを奪い合って確実に壊れる**ので先に終了させる。

### ログ

```sh
ls -t ~/Library/Logs/MenuBarTidy-dev/ | head -1
grep -iE "controlitem|occlu|temporarilyShow|AX activation" ~/Library/Logs/MenuBarTidy-dev/<最新>.log
```

`is occluded — the menu bar accepted the status item but is not rendering it` は
`ControlItemOcclusion` による警告。ノッチ付きディスプレイでバーが溢れているときに出る。

**常用版（Release）はログが既定で無効**。常用版でしか再現しない・再現が稀な現象
（レイアウト画面の表示だけがメニューバーとずれる等）は、先に有効化して再起動し、
次の再現を待つ:

```sh
defaults write com.nyshk97.MenuBarTidy EnableDiagnosticLogging -bool true
osascript -e 'tell application "MenuBar Tidy" to quit'; sleep 3; open -g "/Applications/MenuBar Tidy.app"
ls -t "$HOME/Library/Logs/MenuBar Tidy/" | head -1
```

レイアウト画面とメニューバーの食い違いを調べるときは `Updated menu bar item cache: visible=N, hidden=M` の
件数と `swift scripts/list-menu-bar-items.swift` の仕切り位置を突き合わせる。
`Not updating menu bar item cache:`（mid expand/collapse）や `serial cache operation already in progress`
の直後に `Updated` が来ていなければ、その回の再キャッシュは捨てられている
（`cacheItemsIfNeeded: window N moved since the last cache` が次の周期で拾う）。
戻すときは `-bool false`。

---

## 6. 文字列

**ローカライズは廃止した。** 文字列カタログは無く、UI に出る文字列は Swift のリテラルに
日本語で直接書いてある。`String(localized:)` も `LocalizedStringKey` もコードに存在しない。

英語が紛れ込んでいないかの走査:

```sh
grep -rnE '(Text|Label|Button|Toggle)\(\s*"[A-Za-z]|withTitle: "[A-Za-z]|\btitle: "[A-Za-z]|(messageText|informativeText)\s*=\s*"[A-Za-z]' --include="*.swift" Thaw \
  | grep -vE 'MenuBarItemTag|iconName|systemSymbolName|accessibilityDescription'
```

- 除外している `MenuBarItemTag` / `iconName` / `systemSymbolName` は**システム側の識別子**で
  UI に出ない。訳してはいけない
- `macOS ...` で始まる行は日本語文の中の英単語なので正常

ローカライズ API が復活していないこと、リソースが混入していないことの確認:

```sh
grep -rn "String(localized\|LocalizedStringKey" --include="*.swift" Thaw   # 0 件
ls -d Build/Build/Products/Debug/MenuBarTidy-dev.app/Contents/Resources/*.lproj   # 「no matches」が正
```

- **`Text("日本語")` は今も `LocalizedStringKey` を経由する**（SwiftUI の型がそうなっている）。
  カタログが無いのでキー自身にフォールバックし、日本語がそのまま出る。ビルド生成物の
  `*.stringsdata` に日本語キーが並ぶのはこのため。異常ではない

---

## 7. 既知の外部要因（アプリのバグではないもの）

**動作確認が失敗したとき、まずここを疑う。** 以下はすべて macOS や他アプリ側の事情で、
コードをいくら直しても消えない。upstream Thaw の `FREQUENT_ISSUES.md` から、このフォークで
実際に踏みうるものだけを抜き出した（削除済み機能・upstream の issue 追跡は落としてある）。

### メニューバーの自動非表示が ON だと項目を並べ替えられない

macOS が「メニューバーを自動的に表示/非表示」中はメニューバーを十分に公開しないため、
項目の移動が一切できない。レイアウト画面に
`MenuBar Tidy は自動的に非表示になるメニューバーではメニューバー項目を整理できません。`
と出る（`MenuBarLayoutSettingsPane.swift:224`）。

System Settings → コントロールセンター → 「メニューバーを自動的に表示/非表示」を
**「しない」**にしてからレイアウトを編集し、必要なら後で戻す。

### レイアウト画面に名前が出ない項目がある

Control Center が肩代わりしてホストしている項目（`com.apple.controlcenter:Item-0` として
出てくるもの）は、安定した識別子を持たないことがある。メニューバーには見えているのに
レイアウト画面では名前で並ばない。**バグではなく識別できていない状態。**

また macOS は一部の**システム項目の ⌘ ドラッグを拒否する**。ドラッグ中はカーソルに付いてくるが、
離すと元に戻る。

### Little Snitch は既知の難物

`at.obdev.littlesnitch.agent` は Control Center 配下に**安定した source PID なしで**現れるため、
バンドルIDではなくマーカーペア照合で間接的に同定している（`MenuBarItem.swift:309-332`、
`LayoutSolver.swift:1366-1469`、`MenuBarItemTag.swift:488` に専用のエイリアス）。
症状は「置いた場所に留まらない」「数分後に非表示セクションへ戻る」「名前で出ない」。

```sh
# 認識が壊れたときのリセット
rm -rf ~/Library/Caches/com.nyshk97.MenuBarTidy.dev
tccutil reset Accessibility com.nyshk97.MenuBarTidy.dev
```

アプリを終了 → メニューバー上で Little Snitch のアイコンを ⌘ ドラッグで右端へ → 再起動、
の順が効くことがある。ログで `obdev` / `littlesnitch` / `marker-pair` を探し、
`at.obdev.littlesnitch.agent` が出てこなければまだ同定できていない。

**クリック転送（§5 の確認項目4）の検証台としては使わないこと。** GUI Scripting を無効にして
出荷されているアプリは合成イベントを黙って捨てるため、イベント層からは成功と区別がつかない
（`ClickReactionVerifier.swift:12-32` がまさにこの問題を扱っている）。転送のテストは
Control Center 以外がホストする普通のアプリで行う。

### Control Center の設定ファイルが壊れると複数アプリが同時に狂う

CodexBar 0.29.x が Control Center の設定に不正な状態を書き込み、**menu bar manager 側では
直せない**ドリフトを起こした事例がある。Little Snitch など Control Center ホストの項目が
**複数同時に**おかしくなったらこれを疑う。

```sh
killall ControlCenter
rm ~/Library/Preferences/com.apple.controlcenter.plist
rm ~/Library/Preferences/ByHost/com.apple.controlcenter*.plist
```

### ディスプレイ構成の変更直後は判定しない

モニタの抜き差し・スリープ復帰・Sidecar・KVM 切り替えの直後は、解像度のちらつきや
一時的な余白が出る。さらに項目間隔の適用が必要な遷移では**メニューバー項目を持つアプリを
再起動する**ため、アイコンが一瞬重複して見える（重複はそのアプリのものでこのアプリのものではない）。
数秒待ってから確認する。

### 画面収録の許可を何度も聞かれる

再起動のたびに再要求される状態になったら、System Settings → プライバシーとセキュリティ →
画面収録 から **MenuBar Tidy を一度削除して追加し直す**。

### iPhone ミラーリング中は正しく測れない

iPhone のライブアクティビティがミラーリングされている間は、メニューバーに隙間や空白が出る
macOS 側の制約がある。ミラーリングを止めてから確認する。

---

## 8. リリース

配布は notarize 済み zip を GitHub Release に上げ、`nyshk97/homebrew-tap` の
`Casks/menubar-tidy.rb` を更新して `brew` から入れる形（新規インストール用）。
日々の更新は Sparkle: 同じ Release に EdDSA 署名付きの `appcast.xml` を添付し、アプリは
`https://github.com/nyshk97/menubar-tidy/releases/latest/download/appcast.xml` を見に行く
（自動確認 ON・ダウンロードは Sparkle のダイアログで確認してから）。

```sh
mise run release            # patch bump。minor / major / x.y.z も指定できる
```

内訳（個別にも回せる）:

| 手順 | コマンド | 何を確かめるか |
| --- | --- | --- |
| ビルド + 署名検証 + zip | `mise run release:zip` | Developer ID 署名・secure timestamp・Hardened Runtime・`get-task-allow` 不在 |
| notarize + staple | `mise run release:notarize` | `spctl --assess` が `Notarized Developer ID` を返すこと |
| EdDSA 署名 + appcast | （`release.sh` 内） | `sign_update --account menubar-tidy` の出力が `sparkle:edSignature=` を含み、`dist/appcast.xml` が `xmllint` を通ること |

- **Release 構成だけ Developer ID 署名**（Debug は Apple Development のまま）。
  `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` で `get-task-allow` の注入を止めてある
- **配布物は常用版の名前・バンドルIDで出る**（`MenuBar Tidy.app` / `com.nyshk97.MenuBarTidy`）。
  dev 版の名前が混ざっていないかは `mise run release:zip` の後に `codesign -dvv` で確認できる
- notarize の資格情報は keychain プロファイル `nyshk97-notary`（`NOTARY_PROFILE` で変えられる）。
  無いときの作り方は §0「開発機を移したとき」を参照（App Store Connect の API キーで登録する）
- **Sparkle.framework の中身は `make-release-zip.sh` が inside-out に再署名する**（`Downloader.xpc` →
  `Installer.xpc` → `Updater.app` → `Autoupdate` → framework → 最後に `.app` 本体）。xcodebuild は
  framework の外側しか署名し直さず、中の XPC が adhoc のまま残って notarize が Invalid になる。
  本体の再署名を忘れると Frameworks/ の変更で外側の seal が壊れ `codesign --verify --deep --strict` で落ちる
- **Sparkle の鍵は dev 版と Release で扱いが違う**: `SUFeedURL` / `SUPublicEDKey` / `SUEnableAutomaticChecks` は
  Release 構成専用の `Thaw/Resources/Info-Release.plist` にだけある（Debug は `Info.plist`。pbxproj の
  `INFOPLIST_FILE` で切り替え。`INFOPLIST_KEY_SU*` は Xcode が任意キーを受けないので使えない）。
  dev 版に入れると dev が常用版のダウンロードで置き換わるので、ビルド後に無いことを確認する:

  ```sh
  /usr/libexec/PlistBuddy -c "Print :SUFeedURL" Build/Build/Products/Debug/MenuBarTidy-dev.app/Contents/Info.plist   # → Does Not Exist
  /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "Build/Build/Products/Release/MenuBar Tidy.app/Contents/Info.plist"  # → feed URL
  ```

  加えて `UpdatesManager.isSupported` が `#if DEBUG` で false になり、dev 版ではアップデータを起動しない（二重防御）
- EdDSA の秘密鍵は keychain の account `menubar-tidy`（`mise run doctor` が見る）。バックアップは
  `~/Library/CloudStorage/Dropbox/secrets/sparkle-ed25519-menubar-tidy-private.key`、
  新しい Mac では `generate_keys --account menubar-tidy -f <そのファイル>` で import する。
  公開鍵は `Info-Release.plist` の `SUPublicEDKey`（鍵を作り直したら必ず対で更新）
- zip 化は `ditto -c -k --sequesterRsrc --keepParent`。`zip -r` は symlink を潰して署名を壊す
- 配布物の最終確認:

```sh
ditto -x -k dist/MenuBarTidy-<version>.zip /tmp/mbt-check
spctl --assess --type execute -vv "/tmp/mbt-check/MenuBar Tidy.app"   # → Notarized Developer ID
```

- リリース後の feed 確認:

  ```sh
  curl -sL https://github.com/nyshk97/menubar-tidy/releases/latest/download/appcast.xml | grep -E "shortVersionString|edSignature"
  ```

  `shortVersionString` が出したバージョン、`enclosure` に `sparkle:edSignature` があること
- **アプリ内更新の本番確認は「次のリリース」でしかできない**: 新版を出したら、旧版を起動したまま
  設定画面の「アップデートを確認」→ 新版のダイアログ → インストール → 再起動後にタイトルの `ver` が
  上がっていること。Sparkle が入る前の版（≤ 1.0.3）からは `brew upgrade --cask nyshk97/tap/menubar-tidy` でしか上がれない

---

## 9. 罠

- **Claude Code の Bash からは `screencapture` が真っ黒になる**（画面収録権限がない）。
  メニューバーの目視確認はユーザーに依頼するか、`scripts/list-menu-bar-items.swift` で代替する
- **バンドルIDを変えると TCC の許可が失効する**。変更は削り込みの早い段階でまとめて済ませる
- **初回起動では全項目が hidden セクションに入る**。仕切りの初期位置が両方とも右端
  （`preferredPosition` visible=0, hidden=1）なので、既存の項目は全部その左に来る。バグではない
