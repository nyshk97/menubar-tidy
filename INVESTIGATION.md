# Thaw コードベース調査（削り込み着手前の記録）

> [!IMPORTANT]
> **これは着手前のスナップショットであり、現在のツリーの説明ではない。**
> ここに書かれた行番号・ファイル構成・「削除候補」はすべて **削り込みを始める前**
> のものなので、そのまま今のコードを探しても見つからない。
>
> 残す理由は、**なぜその機能を削ってよいと判断したか**の根拠がここにしか無いため。
> 現在の構成を知りたいときは [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) を、
> 動作確認の手順は [VERIFY.md](VERIFY.md) を見ること。
>
> 特に、この文書がまだ存在するものとして書いている以下は**すでに削除済み**:
> `ThawCtl/`、`Fuzzing/`、`Thaw/MenuBar/Appearance/`、`Thaw/Hotkeys/`、
> `Thaw/Onboarding/` のツアー、設定画面（レイアウトエディタを除く）、
> URL スキーム、Sparkle、Ice インポート、検索パネル、
> `Thaw/Resources/Localizable.xcstrings`（ローカライズ自体を廃止）。
> `FREQUENT_ISSUES.md` も削除済みで、このフォークで踏みうる分だけ
> [VERIFY.md](VERIFY.md) の「既知の外部要因」へ移してある。

**目的**: `thaw-app/Thaw` を fork し、自分専用の最小構成メニューバーマネージャに作り替えるにあたり、削れる範囲と削ってはいけない中核を特定する。

**調査時点**: 2026-08-17 / `development` ブランチ `ed628596`（upstream と 0 コミット差、fork 後未改変）

**方針**: 読み取りのみ。コードは一切変更していない。事実は `ファイル:行番号` を根拠として添える。確証のない箇所は **推測** と明記する。

---

## 0. 要約（先に結論）

| 項目 | 結論 |
|---|---|
| 総規模 | Swift 374 ファイル / 104,628 行（うちテスト 195 ファイル / 43,433 行） |
| 押し出し方式 | `ControlItem` の `NSStatusItem.length = 10000` + 超ワイド用スペーサー項目 |
| ThawBar クリック転送 | **AX アクション優先 → 合成 CGEvent フォールバック**の2段。項目が画面外なら「一時的に実バーへ移動 → クリック → 復帰」 |
| 中核の実体 | `MenuBarItemManager.swift` **11,493 行**に集中。ここは削れない |
| 最低要件 | **macOS 26.0**（`MACOSX_DEPLOYMENT_TARGET = 26.0`） |
| ライセンス | GPL-3.0。全 371 Swift ファイルに二重著作権ヘッダあり |
| 削減見込み | 「捨てたい機能」を全部落として、残るのは**おおよそ 25,000〜30,000 行**（推測。§5 の分類に基づく） |

**最大の注意点**: 「捨てたい機能」のうち **設定画面そのもの** と **プロファイル** は、独立していない。§5.7 / §5.3 参照。

---

## 1. ディレクトリ構成と各モジュールの責務

```
Thaw/
├── Main/           1,307 行  アプリ起動・AppState（全マネージャの保有）・Sparkle 更新
├── MenuBar/
│   ├── ControlItem/    1,573 行  ★仕切り NSStatusItem。押し出しの実体
│   ├── IceBar/         1,416 行  ★ThawBar パネル（独立バー）
│   ├── MenuBarItems/  18,927 行  ★★中核。項目列挙・移動・クリック・画像キャッシュ
│   ├── Appearance/     3,801 行  メニューバー外観カスタマイズ（オーバーレイパネル）
│   ├── LayoutBar/      2,036 行  設定画面内のドラッグ並べ替え UI
│   ├── Search/         1,240 行  検索パネル
│   ├── Spacing/          544 行  項目間スペーシング（beta）
│   ├── MenuBarManager.swift      1,115 行  ★セクション束ね役・右クリックメニュー
│   ├── MenuBarSection.swift        428 行  ★visible/hidden/alwaysHidden の show/hide
│   └── MenuBarSectionLayout.swift  168 行
├── Events/         3,084 行  ★HID 監視（空欄クリック検出）・CGEventTap
├── Settings/      10,199 行  設定画面 UI + 設定モデル + プロファイル
├── Hotkeys/        1,069 行  ホットキー
├── Permissions/      686 行  ★アクセシビリティ / 画面収録の要求
├── Onboarding/     1,256 行  初回起動ツアー
├── UI/                       共通 SwiftUI 部品
├── Utilities/      5,158 行  Defaults・拡張・ScreenCapture・URI ハンドラ・Ice インポート
└── Resources/                Localizable.xcstrings 1.5MB（20言語）

Shared/             2,455 行  ★Bridging（CGS 私的 API）・WindowInfo・DiagnosticLogger
MenuBarItemService/ 1,063 行  ★XPC ヘルパ。項目の「真の所有プロセス」解決
ThawCtl/              308 行  設定 URI を叩くための別アプリ（デバッグ/連携用）
Fuzzing/                      ファズテスト
```

★ = 残したい5機能に必要。★★ = 中核中の中核。

### 主要クラスの責務

| 型 | ファイル | 責務 |
|---|---|---|
| `AppState` | `Thaw/Main/AppState.swift:18` | 全マネージャを `let` で保有。起動順を `setupTask` で固定（`:100`〜`:135`） |
| `MenuBarManager` | `Thaw/MenuBar/MenuBarManager.swift` | `sections` 配列（visible/hidden/alwaysHidden の3つ、`:137`）と各パネルを保有 |
| `MenuBarSection` | `Thaw/MenuBar/MenuBarSection.swift:13` | セクション1つ分の show/hide。ThawBar かインラインかの分岐を持つ（`:235`） |
| `ControlItem` | `Thaw/MenuBar/ControlItem/ControlItem.swift:16` | 仕切り `NSStatusItem` 1個。length 制御・クリック受け・右クリックメニュー |
| `MenuBarItemManager` | `Thaw/MenuBar/MenuBarItems/MenuBarItemManager.swift` | **11,493 行**。項目キャッシュ・移動・クリック・一時表示・復帰 |
| `MenuBarItemImageCache` | 同 `MenuBarItemImageCache.swift` | 1,970 行。ScreenCaptureKit で項目のアイコン画像を取得しキャッシュ |
| `IceBarPanel` | `Thaw/MenuBar/IceBar/IceBar.swift` | ThawBar の `NSPanel` + SwiftUI 内容 |
| `HIDEventManager` | `Thaw/Events/HIDEventManager.swift` | 2,003 行。マウス監視。空欄クリック・ホバー・スクロールの入口 |

---

## 2. 「押し出し方式」の実装箇所

### 2.1 長さの定義

`Thaw/MenuBar/ControlItem/ControlItem.swift:57-60`:

```swift
private nonisolated enum Lengths {
    static let standard: CGFloat = NSStatusItem.variableLength
    static let expanded: CGFloat = 10000
}
```

`identifier.length(for:)`（`:38-47`）が、`hidden` / `alwaysHidden` の control item に対して:
- `.showSection` → `standard`（可変長 = 実質ゼロ幅の仕切り）
- `.hideSection` → `expanded` = **10000pt**

を返す。この 10000pt が右側の項目を画面外へ押し出す。

### 2.2 length を実際に適用する場所

`ControlItem.updateStatusItemVisibility(_:)` — `Thaw/MenuBar/ControlItem/ControlItem.swift:672-698`

```swift
if isVisible {
    constraint?.isActive = true
    statusItem.length = identifier.length(for: state)      // ← :679
    let shouldUseSpacers = (identifier == .hidden || identifier == .alwaysHidden) && state == .hideSection
    updateSpacerItems(forHiddenState: shouldUseSpacers)     // ← :682
} else {
    ...
    statusItem.length = shouldShow ? 3 : 0                 // ← :691
}
```

同じファイルのドキュメントコメント（`:664-671`）に設計意図が明記されている:

> The hidden and always-hidden control items **must always be present in the menu bar**, as we use their positions to determine the items in each section. Setting `statusItem.isVisible` to `false` completely removes the item.

つまり **仕切りは常に存在し続ける必要がある**。セクション判定（どの項目がどのセクションに属するか）が仕切りの X 座標に依存しているため。判定本体は `MenuBarItemManager.ItemCache.findSection(for:)` — `MenuBarItemManager.swift:2690`。

### 2.3 超ワイドディスプレイ用スペーサー

`ControlItem.updateSpacerItems(forHiddenState:)` — `ControlItem.swift:701-733`、`requiredSpacerCount()` — `:744-753`

画面幅が 5120pt を超える場合、10000pt では押し出しきれないので、追加の不可視 `NSStatusItem`（`autosaveName` = `"...Spacer.N"`）を必要数生成し、それぞれ length 10000 を割り当てる。目標幅は `maxScreenWidth * 3`。

**残すべきか**: 5K 超のディスプレイを使わないなら不要。ただし 60 行程度なので消すメリットは薄い。

### 2.4 仕切り位置の永続化

- `ControlItemDefaults` — `ControlItem.swift:1101` 以降。`NSStatusItem.autosaveName` に紐づく `preferredPosition` を UserDefaults 経由で読み書きする薄いラッパ。
- キー: `ControlItem.Identifier.rawValue` = `"Thaw.ControlItem.Visible"` / `.Hidden"` / `.AlwaysHidden"`（`:19-24`）
- 初期シード: `preflightSetup(for:)` — `:1176-1201`。visible は 0、hidden は 1。
- `statusItem.isVisible = false` は preferredPosition を**消してしまう**副作用があるため、`removeFromMenuBar()`（`:764-786`）でキャッシュ→復元している。issue #890 の対策。

**つまり位置の永続化は AppKit の autosave 機構そのものであり、自前の UserDefaults 実装ではない**。「仕切り位置のみ UserDefaults」という構想は、実際には「AppKit に任せ、消える副作用だけ手当てする」という形で既に実現されている。ここは触らないのが安全。

---

## 3. ThawBar の実装

### 3.1 パネルの生成と表示

- `IceBarPanel: NSPanel` — `Thaw/MenuBar/IceBar/IceBar.swift`
- 表示: `IceBarPanel.show(section:on:triggeredByHotkey:)` — `:204-273`
  1. `navigationState.isIceBarPresented = true`、`currentSection = section` を**先に**設定（`:226-228`。コメントで「IMPORTANT」と明示）
  2. `IceBarHostingView` を組み立て（`:232-237`）
  3. `updateOrigin(for:)` で位置決め（`:239`、実装は `:114-160`）
  4. `colorManager.updateAllProperties` → `orderFrontRegardless()`（`:249-251`）
  5. **バックグラウンドで** 一時表示中項目の復帰 → 500ms 待ち → 項目キャッシュ更新 → 画像キャッシュ更新（`:258-272`）

### 3.2 項目の矩形取得（CGWindowList 系）

- 入口: `MenuBarItem.getMenuBarItems(on:option:)` — `Thaw/MenuBar/MenuBarItems/MenuBarItem+Enumeration.swift:357`
- ウィンドウ列挙: `getMenuBarItemWindows(on:option:)` — 同 `:121`
- 実際の CG 呼び出しは `Shared/Bridging/Bridging.swift`（975 行）にまとめられている。`Shared/Bridging/Shims.swift` が `@_silgen_name` で CGS 私的 API を直接引いている（`Shims.swift:40-97`: `CGSMainConnectionID`, `CGSCopyActiveMenuBarDisplayIdentifier`, `CGSGetActiveSpace`, `CGSEventIsAppUnresponsive` 等）
- 生の bounds は `Bridging.getWindowBounds(for:)`。座標系は **CoreGraphics グローバル・左上原点**（`AXItemActivator.swift:113-115` に明記）
- 所有プロセスの解決には別プロセスの XPC ヘルパ `MenuBarItemService` を使う（`MenuBarItem+Enumeration.swift:252`）。CG ウィンドウと AX 要素を空間マッチングして「見かけの owner（Control Center など）」ではなく「真の source PID」を割り出す（`MenuBarItemService/SourcePIDCache.swift`、884 行）

### 3.3 画像キャッシュ

- `MenuBarItemImageCache` — 1,970 行
- 取得は **ScreenCaptureKit**: `ScreenCapture.captureWindowsAsync(with:screenBounds:option:)`（`Thaw/Utilities/ScreenCapture.swift:130`）→ `MenuBarItemImageCache.compositeCapture` `:909-937`
- 2 モード: まとめて撮って切り出す `compositeCapture`（`:909`）と、1個ずつ撮る `individualCapture`（`:1067`）
- ディスク永続化あり: `saveToDisk()` `:349` / `loadFromDisk()` `:393`
- 失敗記録・LRU・メモリ圧対応あり（`:1395`, `:1459`, `:1441`）

**画面収録権限が要るのはここ**。権限がないと ThawBar はアイコンを描けず「Unable to display」になる（`IceBar.swift:591`, `:614`）。

### 3.4 描画の流れ

```
IceBarPanel.show()
  └ IceBarHostingView (IceBar.swift:323)
      └ IceBarContentView (:358 付近)
          ├ itemManager.itemCache[section] で対象項目リストを取得
          ├ imageCache.images[item.tag] で画像を引く (:432, :819)
          └ 各項目を IceBarItemView で描画 (:723 付近)
              └ IceBarItemClickView (NSViewRepresentable, :879) がクリックを受ける
```

レイアウトは行/グリッド両対応（`IceBarLayout.swift`、`gridColumns` 設定 `IceBar.swift:387`）。背景色は `IceBarColorManager`（280 行）が**メニューバー下の画面をキャプチャして**平均色を出している（`IceBarColorManager.swift:216` で `ScreenCapture.captureWindowsAsync`）。

---

## 4. ★最重要★ ThawBar 上のクリックを実項目に転送する処理

### 4.1 入口

`IceBar.swift:742-776` — `IceBarItemView.leftClickAction`

```swift
private var leftClickAction: () -> Void {
    { ...
        if let liveItem = await liveOnScreenItem(matching: item, on: displayID) {
            try await itemManager.click(item: liveItem, with: .left)      // :758  ← 経路A
        } else {
            let result = await itemManager.temporarilyShow(
                item: item, clickingWith: .left, on: displayID, fastPath: true)  // :770 ← 経路B
        }
    }
}
```

右クリックも同構造（`:778-800`）。分岐は「その項目が**今スクリーン上にあるか**」（`liveOnScreenItem(matching:on:)` — `:809`）。

- ThawBar を開くと `MenuBarSection.show()` が hidden/alwaysHidden の control item を `.hideSection` に保つ（`MenuBarSection.swift:286-295`）ので、**隠れている項目は画面外**にある。したがって通常は**経路B**が走る。
- 経路A は、項目が何らかの理由で実バー上にも見えている場合の近道。

### 4.2 経路A: `MenuBarItemManager.click(item:with:)`

`Thaw/MenuBar/MenuBarItems/MenuBarItemManager.swift:6066-6170`

**2段構え**になっている。

**第1段: アクセシビリティ・アクション**（`:6076-6096`）

```swift
if mouseButton == .left, appState.settings.advanced.useAXClickDelivery == true {
    let snapshot = ClickReactionVerifier.snapshot(for: item)
    do {
        try await AXItemActivator.activate(item: item)     // :6079
        return await ClickReactionVerifier.verify(against: snapshot)
    } catch { ... フォールバックへ ... }
}
```

`AXItemActivator.activate(item:)` — `Thaw/MenuBar/MenuBarItems/AXItemActivator.swift:54-77`:

1. `resolveElement(for:)`（`:118-152`）で AX 要素を解決
   - まず systemwide 要素を項目の中心座標でヒットテスト（`AXHelpers.element(at:)`）
   - 失敗したら owner アプリの extras menu bar の子要素から、中心座標を含む frame を探す
2. AX frame と項目の `bounds` が ±10pt 以内で一致するか検証（`framesMatch`、`:38`, `:163`）。ズレていたら `frameMismatch` で中止（誤爆防止）
3. `AXShowMenu` → 失敗したら `AXPress` の順で試す（`performFirstEffectiveAction`、`:97-110`）
4. メッセージングタイムアウトは **0.25 秒**（`:42`）

**右クリックには AX 経路がない**（`mouseButton == .left` 条件）。右クリックは常に合成イベント。

**第2段: 合成 CGEvent**（`:6098-6167` → `postClickEvents`）

`postClickEvents(item:mouseButton:)` — `:5852-5951`:

1. `eventSemaphore` を 3.5 秒タイムアウトで取得（`:5858`）。1回リトライ
2. `getCurrentBounds(for: item).center` でクリック座標を取る（`:5874`）
3. `CGEvent.menuBarItemEvent(item:source:type:location:)` で mouseDown / mouseUp を生成（`:5888-5900`）
4. **カーソルを実際にワープさせる**（`:5906` `MouseHelpers.warpCursor(to: clickPoint)`）
5. 10ms 待つ（`:5910`。コメント: warp を Window Server が処理する前にイベントを投げると、カーソルの**古い位置**（Apple メニュー等）にルーティングされる）
6. カーソルを隠す → `defer` で元位置に戻して再表示（`:5911-5916`）
7. `postEventWithBarrier(mouseDown, ...)` → `postEventWithBarrier(mouseUp, ..., repeating: 2)`（`:5920-5931`）
   - **mouseUp は2回**投げる。コメント: "Double mouse up prevents invalid item state."
8. 失敗したら mouseUp だけもう一度投げるフォールバック（`:5936-5943`）

**イベントの細工** — `CGEvent.menuBarItemEvent` `:11395-11411`、`setWindowID` `:11469-11479`:

```swift
setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)
if case .move = type { setIntegerValueField(.windowID, value: windowID) }   // 生の 0x33 フィールド
```

つまり **対象項目の CGWindowID をイベントに直接刻印**して、WindowServer のヒットテストに頼らず配送している。`setUserData` で自前イベントの識別子も入れており（`:11463`）、これは自分が投げたイベントをイベントタップで検出して「配送完了」を確認するため（`makeContinuationEventTaps` `:4670`、`awaitEventContinuation` `:4716`）。

**結果検証**: `ClickReactionVerifier`（`Thaw/MenuBar/MenuBarItems/ClickReactionVerifier.swift`、244 行）。「イベントが受理された」と「アプリが反応した」を区別する。反応の証拠は (a) 新しいウィンドウが画面に出た (b) 項目自身のウィンドウのサイズが変わった／消えた の2つのみ。反応なしは**失敗の証明とは扱わない**（`:39-42`）。

### 4.3 経路B: `temporarilyShow(item:clickingWith:on:fastPath:)`

`MenuBarItemManager.swift:6657-` （関数は長大。以下は主要ステップ）

**質問への直接の回答: length を戻すのではなく、項目そのものを合成ドラッグで物理的に移動させている。**

1. 表示先ディスプレイを解決（`:6767-6774`）
2. 元のセクションを記録（`:6779`）
3. 既存の一時表示項目を強制復帰（`:6787-6805`）
4. その表示の項目一覧を取得（`:6808`）
5. **復帰先**を決める（`getReturnDestination` — `:6458`）。左右の隣接項目を記録
6. **移動先アンカー**は visible control item（Thaw アイコン）の左（`:6819-6828`）
   ```swift
   let moveDestination: MoveDestination = .leftOfItem(anchor)
   ```
7. 復帰情報を **UserDefaults に永続化**（`pendingRelocations` / `pendingReturnDestinations`、`:6832-6847`）
   - 理由（`:6829-6832` コメント）: macOS は Cmd+ドラッグで設定された物理位置を永続化するので、復帰前にアプリが終了すると次回起動時も可視セクションに残ってしまう
8. `hidEventManager.stopAll()`（`:6849`）— 自分の監視を止める
9. **`move(item:to:on:skipInputPause:maxMoveAttempts:)`** で実移動（`:6863-6867`）。fastPath なら試行2回、通常は8回
10. 移動後、位置が落ち着くのを待つ（fastPath: `waitForItemToLeaveOrigin` 最大150ms、`:6928`。通常: `waitForItemPositionToSettle` 250ms + 25ms、`:6944`, `:6955`）
11. **項目を再取得**（移動後の新しい bounds が要るため、`:6932-6937` / `:6948-6953`）
12. Electron 製なら AX press、それ以外は合成クリック（`:6968-6975` 付近）
13. 開いたウィンドウを記録し、`TemporarilyShownItemContext` を積む（`:6825` 付近で生成）
14. `runRehideTimer(for: rehidePollInterval)` で復帰ポーリング開始（`:6912`）

**移動の実体** — `postMoveEvents(item:destination:on:warpCursorAfter:)` `:5174-5300+`:

- 対象 PID の死活確認（`kill(pid, 0)`、`:5205`）と応答性確認（`Bridging.isProcessUnresponsive`、`:5216`）で早期失敗
- **destination の座標**で mouseDown / mouseUp を投げる。ドラッグのジェスチャではない（`:5228-5236` のコメント）:
  > Press and release at the *destination* ... with the moved item's window ID stamped on the press, **relying on the owner to relocate its item to the press location**.
- イベントには `.move` フラグ（Cmd 修飾。`MenuBarItemEventType.cgEventFlags` 経由）が付く

**復帰**: `rehideTemporarilyShownItems(force:isCalledFromTemporarilyShow:)` `:7036`。約15秒（`Defaults.DefaultValue.rehideInterval = 15`、`Defaults.swift:173`）またはフロントモストアプリ変更で発火（`:6620-6628`）。

### 4.4 既知のバグ・不安定さ（コメント・issue 参照）

コード内の issue 参照を機械的に抽出した結果（クリック/移動経路に関わるもの）:

| issue | 箇所 | 内容 |
|---|---|---|
| **#924** | `AXItemActivator.swift:95`, `MenuBarItemManager.swift:6194, 6269, 6422, 6614, 7063` | **最も重い既知バグ**。サードパーティ項目の AX メニューがモーダルループに入ると AX メッセージに応答できず、タイムアウト＝失敗と誤読される。すると `AXPress` でメニューが閉じ、フォールバックの合成クリックでまた開閉し、**ユーザーには「メニューが出て1秒で消える」と見える**。対策として `performFirstEffectiveAction` が「アクションが受理された **or** 項目が反応した」の両方を成功と見なすようにしてある |
| **#881** | `MenuBarItemManager.swift:5230-5236, 3715, 7322` | **移動にウォームアップが必要な問題が未解決**。「観測された全ての移動で、1回目の press は項目を1px 動かすだけで、2回目でようやくテレポートする。ドラッグジェスチャ形状も試したが直らず撤回。**the warm-up attempt remains an open problem**」 |
| #923 | `MenuBarItemManager.swift:4916` | ゼロ幅の仕切りは AppKit にヒットテスト幅を与えないため、ドロップがどちら側か判定できない。±1pt バイアスで回避 |
| #723 | `MenuBarItemManager.swift:5290` | 一括適用中にカーソル hide の refcount がウォッチドッグでリセットされると、カーソルが全項目の移動に合わせて画面上を「引きずられる」 |
| #905 | `MenuBarItemManager.swift:5541` | move 関連 |
| #889 | `MenuBarItemManager.swift:5689` | 起動時レイアウト / move ループ（最近のコミット `500559bc` が対応） |
| #900, #899, #851, #849, #885, #736, #784 | 多数 | キャッシュ・セクション判定・起動時の各種レース |

**Little Snitch は個別対応が必要な既知ケース**（`MenuBarItemManager.swift:5211-5215`。GUI Scripting 無効で出荷されているため合成イベントに応答しない）。`FREQUENT_ISSUES.md:94` にも専用セクションがある。

**Electron/Chromium 製トレイ項目も合成クリックを無視する**（`isElectronItem` — `MenuBarItemManager.swift:5988`、判定は Electron framework の同梱有無）。AX press が必須。

**評価（推測）**: クリック転送はこのプロジェクトで最も複雑かつ最も壊れやすい部分で、`MenuBarItemManager.swift` 11,493 行の相当部分がその周辺の防御コードで占められている。「最小構成に削る」際にここを自前で書き直すのは強く非推奨。**丸ごと残すのが唯一の現実的な選択肢**と考える。

---

## 5. 「捨てたい機能」の削除可否分類

### 分類サマリ

| 機能 | 判定 | 主な理由 |
|---|---|---|
| メニューバー外観カスタマイズ | 🟡 ほぼ独立 | ThawBar の背景色が `appearanceManager.configuration` を読む |
| ホットキー | 🟢 独立 | `HotkeyAction.perform` から既存 API を呼ぶだけ |
| 検索パネル | 🟢 独立 | 参照は3箇所のみ |
| プロファイル / レイアウト切替 | 🔴 **結合** | `LayoutSolver` を共有。右クリックメニューにも埋まっている |
| always-hidden セクション | 🔴 **結合** | `MenuBarSection.Name` の enum ケース。全域に分岐が散る |
| ホバー表示・スクロール表示 | 🟢 独立 | `HIDEventManager` のハンドラ単位で切れる |
| インライン展開 | 🟡 分岐削除で可 | `MenuBarSection.show()` の片側を消す |
| 設定画面 | 🔴 **結合** | 設定モデルがコアから読まれる。UI だけ消せる |
| Ice インポート | 🟢 独立 | |
| 自動アップデート | 🟢 独立 | Sparkle は SPM 依存 |
| オンボーディング | 🟡 ほぼ独立 | 権限要求フローの入口を兼ねている |

凡例: 🟢 安全に削除可 / 🟡 少量の手当てで削除可 / 🔴 中核と結合。安易に削ると壊れる

---

### 5.1 メニューバー外観カスタマイズ — 🟡 ほぼ独立

**対象**: `Thaw/MenuBar/Appearance/` 3,801 行、`Thaw/Settings/SettingsPanes/MenuBarAppearanceSettingsPane.swift`

**被参照** (`grep appearanceManager`):
- `Thaw/UI/Views/MenuBarItemContainer.swift:23, 44, 49` — 描画モディファイア
- `Thaw/MenuBar/IceBar/IceBar.swift:374-375, 406` — **ThawBar が読んでいる**
  ```swift
  private var configuration: MenuBarAppearanceConfigurationV2 {
      appState.appearanceManager.configuration          // IceBar.swift:375
  }
  ...
  return menuBarHeight - appState.appearanceManager.menuBarInsetAmount * 2   // :406
  ```
- `Thaw/Settings/Models/ProfileManager.swift` 多数 — プロファイルが外観設定を保存

**削除手順（推奨）**: `MenuBarOverlayPanel.swift`（1,434 行）と `MenuBarAppearanceEditor/`（1,163 行）を消し、`MenuBarAppearanceManager` は**残して定数を返すスタブに縮める**。ThawBar 側の2箇所の参照をハードコード値に置き換えれば `MenuBarAppearanceManager` も消せる。

`MissionControlDetector.swift`（303 行）は外観オーバーレイの表示制御用。**推測**: オーバーレイを消せば不要だが、他に参照がないか要確認。

### 5.2 ホットキー — 🟢 独立

**対象**: `Thaw/Hotkeys/` 1,069 行、`Thaw/Settings/SettingsPanes/HotkeysSettingsPane.swift` 263 行、`Thaw/Settings/Models/HotkeysSettings.swift` 109 行

`HotkeyAction.perform(appState:)`（`Thaw/Hotkeys/HotkeyAction.swift:34-67`）は既存 API を呼ぶだけの薄い層。逆方向の依存は以下だけ:

- `MenuBarManager.swift` — `rebuildItemHotkeys()`（`:160`）で項目ごとのホットキーを登録
- `ControlItem.swift` — メニュー項目にショートカット表示
- `AppDelegate.swift` — 登録

**削除可**。`rebuildItemHotkeys()` の呼び出し（`MenuBarManager.swift:160`）を消す。

### 5.3 検索パネル — 🟢 独立

**対象**: `Thaw/MenuBar/Search/` 1,240 行

被参照は3箇所のみ:
- `Thaw/MenuBar/MenuBarManager.swift:131` (`let searchPanel = MenuBarSearchPanel()`), `:155` (setup)
- `Thaw/MenuBar/ControlItem/ControlItem.swift:902, 1063` — 右クリックメニューの項目
- `Thaw/Hotkeys/HotkeyAction.swift:56`

**削除可**。

なお `Thaw/Settings/Search/`（1,340 行、`SearchIndex.swift` 883 行）は**設定画面内の検索**であって別物。設定画面を消すなら一緒に消える。

### 5.4 プロファイル / レイアウト切替 — 🔴 結合

**対象**: `Thaw/Settings/Models/ProfileManager.swift` 894 行 + `ProfileManager+Live.swift` 532 行 + `Profile.swift` 611 行 + `ProfileSettingsPane.swift` 531 行 + `ProfilePreviewView.swift` 255 行 = **約 2,800 行**

**結合点**:

1. **右クリックメニューに埋まっている**
   - `Thaw/MenuBar/MenuBarManager.swift:727-754`, `:819-831`
   - `Thaw/MenuBar/ControlItem/ControlItem.swift:964-992`
   → メニュー生成コードの一部を削るだけで済む。難易度低。

2. **`LayoutSolver` を共有している** ← ここが本丸
   - `Thaw/MenuBar/MenuBarItems/LayoutSolver.swift` は **1,984 行**の純関数ライブラリ
   - `MenuBarItemManager` から **42 箇所**呼ばれる（`LayoutSolver.planSectionOrder`, `.hiddenSectionHasRoom`, `.isOnScreen`, `.planLCSMoveSequence`, `.canonicalizedSectionOrder` など）
   - `ProfileManager` からも 5 箇所、`Profile.swift` から 2 箇所
   → **LayoutSolver 自体は削れない**。プロファイル側の呼び出しだけ消える。

3. **`MenuBarItemManager` にプロファイル適用状態が組み込まれている**
   - `:521-579` — `profileSortedItemIdentifiers`, `profileResortTask`, `profileApplyToken`, プロファイル適用のスナップショット
   - `:446-455` — 「アクティブプロファイル再ソート」がキャッシュサイクルのゲートを兼ねている旨のコメント
   → **推測**: ここを消すとキャッシュサイクルのアーム/ディスアームのロジックに穴が開く可能性がある。`armProfileState` 周辺を読んでから判断すべき。

**推奨**: プロファイル UI と `ProfileManager` は消す。`MenuBarItemManager` 内のプロファイル状態変数は**残したまま「常に空」で運用する**（デッドコードとして許容）のが安全。積極的に剥がすなら別タスクとして切る。

### 5.5 always-hidden セクション — 🔴 結合

**対象**: 概念としては設定 `enableAlwaysHiddenSection`（既定 `false`、`Defaults.swift:177`）だが、**実体は `MenuBarSection.Name` の enum ケース**。

**結合の実態**:

- `MenuBarManager.sections` は3要素固定（`MenuBarManager.swift:137-141`）
- `ControlItem.Identifier` に `.alwaysHidden` ケース（`ControlItem.swift:23`）
- `MenuBarSection.swift` の `isHidden`（`:114-137`）、`show()`（`:325-333`）、`totalItemsWidthToShow()`（`:73-77`）に個別分岐
- `HIDEventManager.swift:871-905` — ダブルクリック / Option クリックのハンドラ
- `ControlItem.swift:838-866` — 同上
- `MenuBarItemManager` の itemCache は3セクション前提

**評価**: 設定で `false` にすれば **UI 上は存在しない**（`isEnabled` ガードが各所にある）。**コードから enum ケースごと消すのは、`MenuBarItemManager` のセクション判定・順序保存・復帰先解決すべてに波及するため高リスク。**

**推奨**: `enableAlwaysHiddenSection = false` をハードコードし、**コードは残す**。3個目の control item は生成されるが length 0 で不可視（`ControlItem.swift:691`）。実害は `NSStatusItem` が1個余分に存在することだけ。

**ただし注意（推測）**: 「自アプリのアイコンを常時1個だけ表示」という要件に対し、実際には status item が **3個**（visible + hidden + alwaysHidden）存在する。可視なのは visible の1個だけなので要件は満たすが、他アプリのメニューバー管理ツールから見ると3個見える。

### 5.6 ホバー表示・スクロール表示 — 🟢 独立

**対象**:
- `HIDEventManager.handleShowOnHover(appState:screen:)` — `Thaw/Events/HIDEventManager.swift:1407-1527`
- `handlePreventShowOnHover(with:appState:screen:)` — `:1531-1575`
- `handleShowOnScroll(...)` — `:1579-1603`
- `scheduleHoverRearmChecks(appState:)` — `:791-844`
- `needsMouseMovedTap(appState:)` — `:471-485`
- 関連設定: `showOnHover`（既定 `false`）、`showOnScroll`（既定 `true`）— `Defaults.swift:169-170`

ハンドラ単位で切れる。`mouseMoved` タップと `scrollWheel` モニタも合わせて落とせば**CPU 負荷が下がる副次的メリット**がある。

**メニューバーツールチップ**（`handleMenuBarTooltip` `:1625-1716`）もホバー由来。一緒に消せる。

### 5.7 インライン展開 — 🟡 分岐削除で可

**対象**: `MenuBarSection.show()` の非 ThawBar 側 — `Thaw/MenuBar/MenuBarSection.swift:317-338`

現状の分岐（`:246-280`）:
```
useIceBar が true                     → .iceBar
そうでなければ presentationMode(on:)  → .inline / .inlineHidingApplicationMenus / .iceBar
  （幅が足りなければ自動で .iceBar にフォールバック）
```

**ThawBar 一本化の方法**: `MenuBarSection.useIceBar`（`:31-46`）を `true` 固定にする。これで `presentationMode` 経路に入らない。

**併せて不要になるもの**:
- `MenuBarSectionLayout.swift` 168 行（`presentationMode` の純関数）
- `MenuBarManager.hideApplicationMenus()` / `toggleApplicationMenus()` 一式
- `HotkeyAction.toggleApplicationMenus`
- 設定 `hideApplicationMenus`（既定 `true`、`Defaults.swift:182`）

**注意**: `useIceBar` は `DisplaySettingsManager`（ディスプレイごとの設定、782 行）を経由して読まれている（`MenuBarSection.swift:38-39`）。ここをハードコードするなら `DisplaySettingsManager` への依存も同時に切る。ただし `IceBar.swift:198, 383, 387, 391` が `iceBarLocation` / `iceBarLayout` / `gridColumns` / `itemSpacingOffset` を同じマネージャから読んでいるので、**`DisplaySettingsManager` を消すなら ThawBar 側4箇所もハードコードが必要**。

### 5.8 設定画面そのもの — 🔴 結合

**対象**: `Thaw/Settings/` 10,199 行

**結合の実態**: 「設定画面 UI」と「設定モデル」が同じディレクトリに同居していて、**モデル側はコアから読まれている**。

コアから読まれる設定（抜粋）:

| 読み手 | 設定 |
|---|---|
| `ControlItem.swift:601` | `settings.general.showIceIcon` |
| `ControlItem.swift:640, 686` | `settings.advanced.showAllSectionsOnUserDrag` |
| `ControlItem.swift:840, 852` | `useDoubleClickToShowAlwaysHiddenSection`, `useOptionClickToShowAlwaysHiddenSection` |
| `MenuBarItemManager.swift:6076` | `settings.advanced.useAXClickDelivery` ← **クリック転送の分岐** |
| `MenuBarSection.swift:38-39, 210-211, 222` | `displaySettings.useIceBar(for:)` ほか |
| `HIDEventManager.swift:474, 579, 1500, 1538, 850` | `showOnClick`, `showOnHover`, `useIceBar` ほか |
| `MenuBarManager.swift:265, 468, 598` | `displaySettings.configurations` |

**削除手順**:
1. `Thaw/Settings/SettingsPanes/`、`Thaw/Settings/Search/`、`SettingsView.swift`、`SettingsWindow.swift` は **消せる**（約 6,500 行）
2. `Thaw/Settings/Models/` の `GeneralSettings` / `AdvancedSettings` / `DisplaySettingsManager` は**残すか、定数を返す構造体に置き換える**
3. `IceApp.swift:31` の `SettingsWindow(appState:)` シーンを外す
4. `AppDelegate.swift:131, 325` の `openSettingsWindow()` を無効化

**併せて不要になるもの**:
- `SettingsURIHandler.swift` 1,419 行 + `SettingsURIParser.swift` 132 行（URI で設定を変える機構）
- `ThawCtl/` 308 行（その URI を叩く別アプリ）
- `HookRunner.swift` 257 行 + `AutomationSettings` + `HookScript`（自動化フック）
- `Thaw/MenuBar/LayoutBar/` 2,036 行（設定画面内のドラッグ並べ替え UI）
  - ただし `Thaw/UI/Views/MenuBarItemContainer.swift` と `MenuBarItem.swift`、`MenuBarItemManager.swift` からも `LayoutBar` 名の参照がある。**要確認**

**大きな副作用**: `Localizable.xcstrings` は **1.5MB / 20言語**。設定画面を消せばほとんどの文字列が不要になるが、参照されなくなるだけでファイルは残る。放置で害はない。

### 5.9 Ice からの設定インポート — 🟢 独立

**対象**: `Thaw/Utilities/IceSettingsImporter.swift` 226 行

被参照:
- `Thaw/Permissions/PermissionsView.swift:30`
- `Thaw/Utilities/Migration.swift:17`（コメントのみ）
- `MenuBarAppearanceConfigurationV1.swift:16`（コメントのみ）

**削除可**。`MenuBarAppearanceConfigurationV1.swift` 141 行も、V1→V2 マイグレーション専用なら一緒に消せる（**推測**。他の参照要確認）。

### 5.10 自動アップデート — 🟢 独立

**対象**: `Thaw/Main/Updates.swift` 235 行、`Thaw/Settings/UpdateConsentSheet.swift` 52 行

Sparkle は SPM 依存（`Thaw.xcodeproj/project.pbxproj:10, 109, 183, 291, 806`）。

**削除手順**: `AppState.swift:61` の `let updatesManager = UpdatesManager()` と `:132` の setup、`AppState.swift:267` の同意フロー、`project.pbxproj` の Sparkle 参照を外す。

**GPL 的にはむしろ削除推奨（推測）**: 自分専用ビルドで upstream の appcast を向いたままにすると、意図せず本家版に上書きされる。

### 5.11 オンボーディング — 🟡 ほぼ独立

**対象**: `Thaw/Onboarding/` 1,256 行

`AppDelegate.swift:117-126` で、初回起動時に `openWindow(.permissions)` を呼んでいる。コメント（`:117-123`）:

> On first launch, walk the user through onboarding — **its final step is where they decide whether to grant permissions**

**注意**: オンボーディングを消すと、**権限付与への導線が消える**。`PermissionsWindow` / `PermissionsView` は残し、オンボーディングツアー（`Tour/` 配下 979 行）だけ消すのが安全。

---

## 6. 必要な権限を要求している箇所

### 6.1 権限モデル

`Thaw/Permissions/AppPermissions.swift:50-61`:
```swift
let accessibility = AccessibilityPermission()
let screenRecording = ScreenRecordingPermission()
...
[accessibility, screenRecording]
```

### 6.2 アクセシビリティ

- 定義: `Thaw/Permissions/Permission.swift:141-160`
  > The Accessibility permission, **required for Thaw to detect, move, and** …（`:143-144`）
- 設定 URL: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`（`:159`）
- **用途**:
  - AX 経由のクリック配送（`AXItemActivator.swift` 全体）
  - `pressItemViaAccessibility` — `MenuBarItemManager.swift:6004`
  - 空欄クリック判定の AX ヒットテスト（`HIDEventManager.swift:1197` `isCursorOverForeignWidgetUIElement`、`:1909` `isMouseInsideApplicationMenuClickRegion`）
  - `Shared/Utilities/AXHelpers.swift`
- **必須**。これがないと項目の移動もクリック転送も成立しない。

### 6.3 画面収録

- 定義: `Thaw/Permissions/Permission.swift:187-193`
- 設定 URL: `...?Privacy_ScreenCapture`（`:187`）
- チェック: `ScreenCapture.checkPermissions()` — `Thaw/Utilities/ScreenCapture.swift:23-49`
  - `SCShareableContent` で自分以外のウィンドウが見えるかを見る。見えなければ `CGPreflightScreenCaptureAccess()` にフォールバック（`:40`）
- 要求: `ScreenCapture.requestPermissions()` — `:65-72`
  > `CGRequestScreenCaptureAccess()` is broken on newer macOS versions. Use `SCShareableContent.getWithCompletionHandler` to trigger the …（`:67-70`）
- **用途**:
  - ThawBar のアイコン画像取得（`MenuBarItemImageCache`）
  - ThawBar の背景平均色（`IceBarColorManager.swift:216`）
- **ThawBar を使うなら必須**。`FREQUENT_ISSUES.md:193` に専用セクションあり。

### 6.4 その他

- 通知権限: `Thaw/UserNotifications/UserNotificationManager.swift`（87 行）。**削除候補**
- `ControlItemOcclusion`（`Thaw/MenuBar/ControlItem/ControlItemOcclusion.swift`）は**権限不要で仕切りの遮蔽を検出する**唯一の手段として設計されている（`:15-19` のコメント）。画面収録が拒否されたときのフォールバックなので、残す価値がある

---

## 7. macOS 最低要件とバージョン依存分岐

### 7.1 最低要件

**macOS 26.0**。`Thaw.xcodeproj/project.pbxproj` の全 8 ターゲット構成で `MACOSX_DEPLOYMENT_TARGET = 26.0`（`:507, 570, 610, 651, 678, 710, 735, 756`）。

README のバッジも `macOS 26+`。

### 7.2 バージョン依存分岐

`@available(macOS ...)` / `if #available(macOS ...)` の出現は **4 箇所のみ**:
- macOS 27 向け: 2 箇所
- macOS 26.0 向け: 2 箇所

デプロイメントターゲットが 26.0 なので、コード内の分岐はほぼ不要になっている。

### 7.3 macOS バージョン依存の実質的な問題

分岐ではなくコメント/挙動の形で埋まっている:

- **macOS 26 の Control Center 項目ホスティング**: `MenuBarItemManager.swift:6721-6731`
  > On macOS 26 Control Center hosts the status item while the app draws the menu, so a lookup keyed on either PID alone misses.
  → これが `interfacePIDs` を Set で持つ理由。#924 の根本原因のひとつ
- **macOS 27 (Golden Gate)**: `FREQUENT_ISSUES.md:25` に専用セクション。upstream に `feat/macos-27-curated` / `feat/macos-27-experimental` ブランチが存在。README から macOS 27 ステータス issue (#687) へリンク
- `ScreenCapture.swift:81` — macOS 26 の `SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:)` に関する注記

**評価（推測）**: macOS 27 対応は upstream でも未完了。fork して独自に削り込むと、macOS 27 対応の upstream 変更を取り込むのが困難になる。**削減の前に、upstream の macOS 27 対応が落ち着くのを待つ選択肢も検討に値する。**

---

## 8. ライセンス（GPL-3.0）とヘッダの扱い

### 8.1 ライセンス

- `LICENSE` = GNU GENERAL PUBLIC LICENSE Version 3（`LICENSE:1-2`）
- 二重の系譜:
  - Ice (Jordan Baird) 2023–2025
  - Thaw (Toni Förster) 2026

### 8.2 ヘッダ

**371 / 374 Swift ファイル**に以下の形式のヘッダが入っている:

```swift
//
//  ControlItem.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
```

（例: `Thaw/MenuBar/ControlItem/ControlItem.swift:1-7`）

### 8.3 fork における義務

GPL-3.0 の性質上:

1. **既存ヘッダの著作権表示は削除できない**。Ice / Thaw 両方の行を残す必要がある
2. 自分の改変を加えたファイルには**自分の著作権行を追記**できる（例: `// Copyright (menubar-tidy) © 2026 <名前>`）
3. **配布しなければ**（自分のマシンで使うだけなら）ソース公開義務は発生しない
4. **配布するなら**: ソース全体を GPL-3.0 で公開する必要がある。「最小構成に削ったもの」も派生物
5. `LICENSE` ファイルはそのまま残す

**実務上の推奨（推測）**:
- リポジトリを private にしたまま自分専用で使うなら、ヘッダを触る必要は一切ない
- public にする場合は、README に「thaw-app/Thaw の fork であること」「GPL-3.0 であること」を明記する。upstream の `.github/CONTRIBUTING.md` や `GOVERNANCE.md` は自分のプロジェクトの規約ではないので、削除または置換すべき
- **アプリ名・バンドル ID・アイコンは変える**（Thaw と同時起動すると `AppDelegate.swift:192` の `terminateOtherInstances()` や、両者が同じ `NSStatusItem` autosave 名前空間を取り合って壊れる。**推測**だが、autosave 名は `"Thaw.ControlItem.*"` とハードコードされている〔`ControlItem.swift:19-24`〕ので、バンドル ID が違っても UserDefaults ドメインが別なら衝突しないはず。ただし両方が同じメニューバーの項目を動かし合う競合は確実に起きる）

---

## 9. 削減計画への所見（推測を含む）

### 9.1 削減量の見積もり（推測）

| 削除対象 | 概算行数 |
|---|---|
| 設定画面 UI（Panes + Search + View/Window） | 6,500 |
| プロファイル（UI + Manager + Model） | 2,800 |
| 外観カスタマイズ（Overlay + Editor） | 2,900 |
| LayoutBar（設定内 UI） | 2,036 |
| SettingsURIHandler + Parser + ThawCtl + HookRunner | 2,100 |
| 検索パネル | 1,240 |
| オンボーディングツアー | 979 |
| ホットキー | 1,069 |
| Ice インポート + Updates + Notifications | 600 |
| ホバー/スクロール/ツールチップ | 500 |
| **合計** | **約 20,700 行** |

残り約 84,000 行（うちテスト 43,000 行）。テストも対応分を削れば、**実装コードは約 25,000〜30,000 行**に落ち着く見込み。

### 9.2 削るべきでないもの（再掲）

- `MenuBarItemManager.swift` 11,493 行 — **クリック転送・移動・キャッシュの本体**
- `LayoutSolver.swift` 1,984 行 — 純関数だが 42 箇所から使われる
- `MenuBarItemImageCache.swift` 1,970 行 — ThawBar のアイコン
- `HIDEventManager.swift` 2,003 行 — 空欄クリック検出。ホバー/スクロール部分だけ削る
- `Bridging.swift` + `Shims.swift` 1,190 行 — CGS 私的 API
- `MenuBarItemService/` 1,063 行 — 真の所有プロセス解決。macOS 26 の Control Center ホスティング対応に必須
- `ControlItem.swift` 1,243 行 — 押し出しの実体

### 9.3 進め方の提案（推測）

1. **まず何も削らずビルド・起動して、5機能が動くことを確認する**。macOS 26 前提なので手元環境の確認が先
2. 削除は**独立度の高いものから**: Ice インポート → 自動更新 → 検索 → ホットキー → ホバー/スクロール → オンボーディングツアー
3. **設定画面は「UI だけ消してモデルは残す」**。モデルを定数化するのは最後
4. **プロファイルと always-hidden は最後まで残す**か、そもそも触らない
5. 各ステップで `ThawTests` を回す（195 ファイル / 43,433 行。削除対象のテストは同時に消す）
6. upstream の macOS 27 対応を取り込む可能性があるなら、削除は**独立したコミットに分け**、リバートしやすくしておく

---

## 付録: 調査で使った主なコマンド

```bash
find . -name '*.swift' -not -path './.git/*' -not -path './Build/*' -exec wc -l {} + | tail -1
grep -rn "useIceBar" --include="*.swift" .
grep -o "LayoutSolver\.[a-zA-Z]*" Thaw/MenuBar/MenuBarItems/MenuBarItemManager.swift | sort | uniq -c
grep -rn "(#[0-9]\+)" --include="*.swift" Thaw/MenuBar/MenuBarItems/MenuBarItemManager.swift
grep -n "MACOSX_DEPLOYMENT_TARGET" Thaw.xcodeproj/project.pbxproj
```
