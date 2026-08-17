# 動作確認手順

`thaw-app/Thaw` のフォークを最小構成に削り込む作業（`INVESTIGATION.md` 参照）用の確認手順。
変更内容に関係する項目だけ実行すればよい。全部を毎回やる必要はない。

---

## 0. 前提

- macOS 26 以上 / Xcode 26 以上（`MACOSX_DEPLOYMENT_TARGET = 26.0`）
- 署名は自分の Team（`VYDUR99LAM`）。ad-hoc にすると TCC の許可がビルドのたびに失効する
- バンドルID `com.nyshk97.Thaw`、表示名 **MenuBar Tidy**、アイコンは**青**
  - 本家 Thaw は `com.stonerl.Thaw` / 表示名 **Thaw** / **アンバー**。System Settings で取り違えないこと

---

## 1. ビルド

```sh
xcodebuild -project Thaw.xcodeproj -scheme Thaw -configuration Debug -derivedDataPath Build build
```

`| tail` や `| grep` に繋ぐときは `set -o pipefail` を付ける。付けないと xcodebuild の失敗が
パイプの終了コードに隠れて「成功」に見える。

---

## 2. テスト

```sh
set -o pipefail
xcodebuild -project Thaw.xcodeproj -scheme Thaw -configuration Debug -derivedDataPath Build test 2>&1 \
  | grep -E "✘|error:|Test run with|TEST (SUCCEEDED|FAILED)"
```

期待値: `✔ Test run with 1742 tests in 218 suites passed`（削り込みで件数は減り続ける）

- **`Executed 0 tests` は無視してよい**。XCTest 側のカウントで、このプロジェクトは swift-testing (`@Test`)。
  実数は `Test run with N tests` の行に出る
- 落ちたテストが自分の変更由来か疑わしいときは `git stash` してベースコミットで同じテストを回す
- **同時に2本走らせない**。同じ `-derivedDataPath` を指す `xcodebuild test` を並行起動すると、
  2つのテストホストがビルド成果物と UserDefaults ドメインを奪い合い、片方が途中で打ち切られて
  `TEST FAILED` を返す（実例: 2235 tests のはずが 782 tests で終了）。**コードの問題と見分けが
  つかない**。実行前に `pgrep -c xcodebuild` で 0 を確認する。件数が想定と違ったら並行実行を疑う

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
pkill -f "menubar-tidy/Build.*Thaw"

# 2. 汚染を検出（既定 false なので 1 なら汚染）
defaults read com.nyshk97.Thaw ShowOnHover

# 3. 汚染していたら退避して削除
defaults export com.nyshk97.Thaw /tmp/thaw-domain-backup.plist
defaults delete com.nyshk97.Thaw
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

---

## 4. アイコンと表示名

```sh
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" Build/Build/Products/Debug/Thaw.app/Contents/Info.plist
codesign -dvv Build/Build/Products/Debug/Thaw.app 2>&1 | grep -E "Identifier|TeamIdentifier"
```

アイコンは**パス基準でキャッシュされる**ので、リビルド後に確認するときは新しいパスへコピーしてから引く:

```sh
FRESH=$(mktemp -d)
cp -R Build/Build/Products/Debug/Thaw.app "$FRESH/check.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$FRESH/check.app"
# NSWorkspace.shared.icon(forFile:) で PNG 化して目視
```

---

## 5. 5つの中核機能（実機確認）

自動化できない。**権限付与は System Settings の手動操作が必須**で、合成クリックでの検証は
ユーザーの実メニューバーを壊すリスクがある。

```sh
open Build/Build/Products/Debug/Thaw.app
```

初回は アクセシビリティ と 画面収録 の両方を許可する。System Settings では
**「MenuBar Tidy」＋青アイコン**を選ぶ（「Thaw」＋アンバーは本家）。

| # | 確認項目 | 期待 |
|---|---|---|
| 1 | 自アプリのアイコン | Control Center の左にキューブが1個 |
| 2 | 押し出し | 仕切りより左の項目がメニューバーから消える |
| 3 | 空欄クリック | ThawBar（独立バー）が出る |
| 4 | **ThawBar 上のクリック転送** | アイコンを押すとそのアプリのメニューが開く |
| 5 | 仕切り位置の永続化 | 再起動しても位置が保たれる |

4 が最重要。`MenuBarItemManager.click(item:with:)`（AX → 合成CGEvent の2段）と
`temporarilyShow(...)`（実バーへ移動→クリック→復帰）の両経路がここに集約されている。

**本家 Thaw が起動中だと両者が同じメニューバーを奪い合って確実に壊れる**ので、先に終了させる。

### ログ

```sh
ls -t ~/Library/Logs/Thaw/ | head -1
grep -iE "controlitem|occlu|temporarilyShow|AX activation" ~/Library/Logs/Thaw/<最新>.log
```

`is occluded — the menu bar accepted the status item but is not rendering it` は
`ControlItemOcclusion` による警告。ノッチ付きディスプレイでバーが溢れているときに出る。

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
ls -d Build/Build/Products/Debug/Thaw.app/Contents/Resources/*.lproj        # 「no matches」が正
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
rm -rf ~/Library/Caches/com.nyshk97.Thaw
tccutil reset Accessibility com.nyshk97.Thaw
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

## 8. 罠

- **Claude Code の Bash からは `screencapture` が真っ黒になる**（画面収録権限がない）。
  メニューバーの目視確認はユーザーに依頼するか、`scripts/list-menu-bar-items.swift` で代替する
- **バンドルIDを変えると TCC の許可が失効する**。変更は削り込みの早い段階でまとめて済ませる
- **初回起動では全項目が hidden セクションに入る**。仕切りの初期位置が両方とも右端
  （`preferredPosition` visible=0, hidden=1）なので、既存の項目は全部その左に来る。バグではない
