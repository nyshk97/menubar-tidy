//
//  list-ax-items.swift
//
//  メニューバーの全項目を、アクセシビリティ（各アプリの AXExtrasMenuBar）から
//  左→右の順に一覧する。読み取りのみ。
//
//      swift scripts/list-ax-items.swift
//
//  ウィンドウ一覧（CGWindowList）では、macOS 26 から他社の項目がすべて
//  「コントロールセンターの Item-0」に見えるので使わない。AX なら持ち主のアプリが取れる。
//
//  出力の読み方:
//    - 画面: 各画面の枠を CG 座標（主画面の左上が原点、下向きが +y）で出す。
//      ノッチがある画面は、ノッチの左右の端も出す
//    - 前面アプリのメニューの右端: これより左にある項目はアプリのメニューに隠れる
//    - band=NO の項目: メニューバーの帯（画面の上端の80pt上〜40pt下）の外にいる。システム設定 → メニューバーで
//      表示を許可していない項目は (-1, 981)、コントロールセンターの空の項目は (0, 982, 0×0)
//    - x が画面の左端より小さい項目: 画面外。押してもメニューが画面外に開く
//
//  ターミナルにアクセシビリティの許可が要る（無いと項目が1つも出ない）。
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

/// NSScreen の枠（左下原点）を CG 座標（主画面の左上原点）に直す。
func cgRect(_ rect: CGRect) -> CGRect {
    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
}

func fmt(_ rect: CGRect) -> String {
    String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", rect.minX, rect.minY, rect.width, rect.height)
}

guard AXIsProcessTrusted() else {
    print("このターミナルにアクセシビリティの許可が無い。システム設定 → プライバシーとセキュリティ → アクセシビリティ")
    exit(1)
}

print("== 画面")
for (index, screen) in NSScreen.screens.enumerated() {
    let frame = cgRect(screen.frame)
    var line = "  [\(index)] \(screen.localizedName)  \(fmt(frame))"
    if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
        line += String(format: "  ノッチ x=%.0f〜%.0f", frame.minX + left.maxX, frame.minX + right.minX)
    }
    print(line)
}

print("== 前面アプリのメニュー")
if let front = NSWorkspace.shared.frontmostApplication {
    let app = AXUIElementCreateApplication(front.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.5)
    let menus = (attr(app, kAXMenuBarAttribute)).flatMap { attr($0 as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] } ?? []
    let frames = menus.map(frame(of:))
    let maxX = frames.map(\.maxX).max() ?? 0
    let minY = frames.map(\.minY).min() ?? 0
    print(String(format: "  %@: %d 個、右端 x=%.0f（y=%.0f）", front.localizedName ?? "?", menus.count, maxX, minY))
}

struct Row {
    let frame: CGRect
    let owner: String
    let bundleID: String
    let identifier: String
    let description: String
    let title: String
    let enabled: Bool
}

var rows: [Row] = []
for app in NSWorkspace.shared.runningApplications {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.2)
    guard let bar = attr(element, "AXExtrasMenuBar"),
          let children = attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else { continue }
    for child in children {
        rows.append(Row(
            frame: frame(of: child),
            owner: app.localizedName ?? "?",
            bundleID: app.bundleIdentifier ?? "-",
            identifier: (attr(child, "AXIdentifier") as? String) ?? "-",
            description: (attr(child, kAXDescriptionAttribute) as? String) ?? "",
            title: (attr(child, kAXTitleAttribute) as? String) ?? "",
            enabled: (attr(child, kAXEnabledAttribute) as? Bool) ?? true
        ))
    }
}

// 本体（ScreenGeometry.menuBarBand）と同じ帯。メニューバーが引っ込んだ画面では、項目が
// 画面の上端より約60pt上にいるので、上にも80pt広げる。
let bands = NSScreen.screens.map { cgRect($0.frame) }.map { CGRect(x: $0.minX, y: $0.minY - 80, width: $0.width, height: 120) }

// 画面外へ溢れた項目も帯の中として数えたいので、見るのは縦位置だけ。
func isInBand(_ row: Row) -> Bool {
    bands.contains { ($0.minY...$0.maxY).contains(row.frame.midY) }
}

print("== 項目（帯の中を左→右、そのあと帯の外）")
print("       x      w      y  band  持ち主 / AXIdentifier / 説明 / タイトル")
for row in rows.sorted(by: { (isInBand($0) ? 0 : 1, $0.frame.minX) < (isInBand($1) ? 0 : 1, $1.frame.minX) }) {
    let inBand = isInBand(row)
    print(String(format: "%8.0f %6.0f %6.0f  %@  ", row.frame.minX, row.frame.width, row.frame.minY, inBand ? "yes " : "NO  ")
        + "\(row.owner) (\(row.bundleID)) / \(row.identifier) / \(row.description) / \(row.title)\(row.enabled ? "" : " [disabled]")")
}
print("total: \(rows.count)")
