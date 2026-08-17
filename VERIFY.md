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

期待値: `✔ Test run with 2388 tests in 302 suites passed`

- **`Executed 0 tests` は無視してよい**。XCTest 側のカウントで、このプロジェクトは swift-testing (`@Test`)。
  実数は `Test run with N tests` の行に出る
- 落ちたテストが自分の変更由来か疑わしいときは `git stash` してベースコミットで同じテストを回す

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

## 6. 罠

- **Claude Code の Bash からは `screencapture` が真っ黒になる**（画面収録権限がない）。
  メニューバーの目視確認はユーザーに依頼するか、`scripts/list-menu-bar-items.swift` で代替する
- **バンドルIDを変えると TCC の許可が失効する**。変更は削り込みの早い段階でまとめて済ませる
- **初回起動では全項目が hidden セクションに入る**。仕切りの初期位置が両方とも右端
  （`preferredPosition` visible=0, hidden=1）なので、既存の項目は全部その左に来る。バグではない
