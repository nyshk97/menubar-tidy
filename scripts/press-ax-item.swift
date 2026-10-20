//
//  press-ax-item.swift
//
//  指定したメニューバー項目に AXPress を送り、そのアプリのウィンドウ（メニュー・
//  パネル）がどこに、どの画面に開いたかを測ってから閉じる。
//
//      swift scripts/press-ax-item.swift                 # 指定できる名前の一覧
//      swift scripts/press-ax-item.swift Pecha "コントロールセンター/Bluetooth"
//
//  名前は「アプリ名」か「アプリ名/説明」。一覧は引数なしで出る。
//
//  判定:
//    - 見える位置に開いた: 開いたウィンドウがどれかの画面と重なる（画面の番号も出す）
//    - 画面外に開いた: 開いたが、どの画面とも重ならない
//    - 何も開かない: 2秒待っても、そのアプリの新しいウィンドウが出ない
//  「見える」はウィンドウの座標からの判定。Claude Code の Bash からは screencapture が
//  真っ黒になるので、目で確かめたいときは画面を見ている人に聞く。
//
//  閉じ方: コントロールセンターは AXCancel、それ以外はそのアプリにだけ Esc を送る
//  （CGEvent.postToPid。ターミナルに Esc が届くと Claude Code が止まるため、全体には投げない）。
//  閉じなければもう一度押す。それでも残ったらそこで止める。
//
//  注意: 押すと実際にメニューが開く。クリックしただけで状態が切り替わる項目
//  （録画の停止など）は、ソースや README で挙動を確かめてから指定する。
//

import AppKit
import ApplicationServices

func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func frame(of element: AXUIElement) -> CGRect {
    var point = CGPoint.zero
    var size = CGSize.zero
    if let value = attr(element, kAXPositionAttribute) { AXValueGetValue(value as! AXValue, .cgPoint, &point) }
    if let value = attr(element, kAXSizeAttribute) { AXValueGetValue(value as! AXValue, .cgSize, &size) }
    return CGRect(origin: point, size: size)
}

func cgRect(_ rect: CGRect) -> CGRect {
    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
}

func fmt(_ rect: CGRect) -> String {
    String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", rect.minX, rect.minY, rect.width, rect.height)
}

struct Item {
    let app: NSRunningApplication
    let element: AXUIElement
    let label: String
    let frame: CGRect
}

func allItems() -> [Item] {
    var items: [Item] = []
    for app in NSWorkspace.shared.runningApplications {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        guard let bar = attr(element, "AXExtrasMenuBar"),
              let children = attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else { continue }
        for child in children {
            let description = (attr(child, kAXDescriptionAttribute) as? String) ?? ""
            let title = (attr(child, kAXTitleAttribute) as? String) ?? ""
            let name = app.localizedName ?? "?"
            let label = description.isEmpty
                ? (title.isEmpty ? name : "\(name)/\(title)")
                : (description == name ? name : "\(name)/\(description)")
            items.append(Item(app: app, element: child, label: label, frame: frame(of: child)))
        }
    }
    return items
}

/// pid が持つ、画面に出ているウィンドウ（ステータス項目そのものを除く）。
func shownWindows(of pid: pid_t) -> [Int: CGRect] {
    let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    var windows: [Int: CGRect] = [:]
    for window in raw where (window[kCGWindowOwnerPID as String] as? pid_t) == pid {
        guard (window[kCGWindowLayer as String] as? Int) != 25,
              (window[kCGWindowIsOnscreen as String] as? Bool) == true,
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
        if rect.width < 5 || rect.height < 5 { continue }
        windows[window[kCGWindowNumber as String] as? Int ?? 0] = rect
    }
    return windows
}

func appeared(pid: pid_t, before: [Int: CGRect]) -> [Int: CGRect] {
    shownWindows(of: pid).filter { id, rect in before[id] != rect }
}

/// メニュー型の項目は、メニューが閉じるまで AXPress が戻らない（1秒でタイムアウトして
/// kAXErrorCannotComplete が返る）。待たされないように別スレッドで送る。
func pressAsync(_ element: AXUIElement) {
    DispatchQueue.global().async {
        AXUIElementSetMessagingTimeout(element, 1.0)
        _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}

func postEscape(to pid: pid_t) {
    let source = CGEventSource(stateID: .hidSystemState)
    for keyDown in [true, false] {
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: keyDown)?.postToPid(pid)
    }
}

guard AXIsProcessTrusted() else {
    print("このターミナルにアクセシビリティの許可が無い。システム設定 → プライバシーとセキュリティ → アクセシビリティ")
    exit(1)
}

let screens = NSScreen.screens.map { cgRect($0.frame) }
let targets = Array(CommandLine.arguments.dropFirst())
let items = allItems()

if targets.isEmpty {
    for item in items.sorted(by: { $0.frame.minX < $1.frame.minX }) {
        print(String(format: "%8.0f  ", item.frame.minX) + item.label)
    }
    exit(0)
}

var summary: [String] = []
for target in targets {
    guard let item = items.first(where: { $0.label == target }) else {
        print("SKIP \(target): 見つからない（引数なしで名前の一覧が出る）")
        continue
    }
    let pid = item.app.processIdentifier
    let before = shownWindows(of: pid)
    pressAsync(item.element)

    var seen: [Int: CGRect] = [:]
    for _ in 1...8 {
        Thread.sleep(forTimeInterval: 0.25)
        seen.merge(appeared(pid: pid, before: before)) { _, new in new }
    }

    let onScreens = seen.values.flatMap { rect in screens.indices.filter { screens[$0].intersects(rect) } }
    let verdict = seen.isEmpty ? "何も開かない"
        : onScreens.isEmpty ? "画面外に開いた"
        : "見える位置に開いた（画面 \(Set(onScreens).sorted().map(String.init).joined(separator: ",")))"
    print("=== \(item.label)（項目 \(fmt(item.frame))）→ \(verdict)")
    for (id, rect) in seen.sorted(by: { $0.key < $1.key }) {
        print("    #\(id) \(fmt(rect))")
    }

    if !seen.isEmpty {
        if item.app.bundleIdentifier == "com.apple.controlcenter" {
            AXUIElementPerformAction(item.element, kAXCancelAction as CFString)
        }
        postEscape(to: pid)
        Thread.sleep(forTimeInterval: 0.6)
        if !appeared(pid: pid, before: before).isEmpty {
            pressAsync(item.element)
            Thread.sleep(forTimeInterval: 1.2)
        }
        if !appeared(pid: pid, before: before).isEmpty {
            print("  !!! 閉じられなかった。ここで止める（手で閉じる）")
            summary.append("\(item.label)\t\(verdict)\t閉じられず")
            break
        }
    }
    summary.append("\(item.label)\t\(verdict)")
    Thread.sleep(forTimeInterval: 0.5)
}

print("\n== まとめ")
summary.forEach { print($0) }
