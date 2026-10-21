//
//  main.swift (menu-preview)
//
//  アプリの一覧メニューに並ぶ中身（区分・表示名）を、アプリを起動せずに出す。
//  本体の Thaw/Items/ のソースをそのまま組み込んでビルドするので、判定・表示名・
//  押す処理は本体と同じコードが動く。
//
//      mise run preview                  # 一覧の中身を出す
//      mise run preview -- --press 検索   # その表示名の項目を、一覧から選んだのと同じ経路で押す
//
//  署名なしでビルドするので、会社貸与PCでもキーチェーンに触れずに回せる。
//  動かすターミナルにアクセシビリティの許可が要る。
//

import AppKit

guard AXIsProcessTrusted() else {
    print("このターミナルにアクセシビリティの許可が無い")
    exit(1)
}

let args = CommandLine.arguments.dropFirst()
let pressTitle = args.first == "--press" ? args.dropFirst().first : nil

let pids = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
let known = ItemScanner.pidsWithMenuBarItems(among: pids)
var items: [MenuBarItem] = []
for pid in known {
    guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
    items += ItemScanner.readItems(pid: pid, bundleID: app.bundleIdentifier, appName: app.localizedName ?? "?")
}
items.sort { $0.info.frame.minX < $1.info.frame.minX }

let screens = ScreenGeometry.current()
let listed = items.filter { ItemRules.isListed($0.info, screens: screens, ownPID: ProcessInfo.processInfo.processIdentifier) }
// アプリと同じく、項目がいる画面で判定する（見つからなければ主画面）。
let screen = ItemRules.screen(for: listed.map(\.info), among: screens, fallback: screens.first ?? ScreenGeometry(frame: .zero, notch: nil))
let front = NSWorkspace.shared.frontmostApplication
let appMenusMaxX = front.flatMap { AXHelper.menusMaxX(of: $0.processIdentifier, within: screen.frame) }
let siblingCounts = Dictionary(grouping: listed, by: \.info.pid).mapValues(\.count)

print("画面: \(screen.frame)  ノッチ: \(screen.notch.map { "\($0)" } ?? "なし")")
print("前面アプリ: \(front?.localizedName ?? "?")  メニューの右端: \(appMenusMaxX.map { "\(Int($0))" } ?? "-")")
print("項目を持つプロセス: \(known.count)  読めた項目: \(items.count)  一覧に載る: \(listed.count)")

var rows: [(ItemVisibility, String, MenuBarItem)] = []
for item in listed {
    let visibility = ItemVisibility.classify(item.info.frame, on: screen, appMenusMaxX: appMenusMaxX)
    rows.append((visibility, ItemRules.title(for: item.info, siblingCount: siblingCounts[item.info.pid] ?? 1), item))
}
// 見えている項目は、アプリでは見出しを付けず区切り線だけで分ける。
for (header, kinds) in [("隠れた項目", [ItemVisibility.hidden, .offScreen]), ("（見出しなし）", [.visible])] {
    let section = rows.filter { kinds.contains($0.0) }
    guard !section.isEmpty else { continue }
    print("== \(header)")
    for (visibility, title, item) in section {
        let note = visibility == .offScreen ? "  ［画面外のため開けません］" : ""
        print(String(format: "  %6.0f  ", item.info.frame.minX) + title + note)
    }
}
let leftOut = items.filter { item in !listed.contains { $0.element == item.element } }
print("== 載せない: " + leftOut.map { "\($0.info.appName)(\(Int($0.info.frame.minX)),\(Int($0.info.frame.minY)))" }.joined(separator: " "))

if let pressTitle {
    guard let (_, _, item) = rows.first(where: { $0.1 == pressTitle }) else {
        print("表示名「\(pressTitle)」の項目が無い")
        exit(1)
    }
    print("押す: \(pressTitle)")
    ItemPresser.press(item)
    // 押す処理は少し遅らせてバックグラウンドで走るので、終わるまで待つ。
    Thread.sleep(forTimeInterval: ItemPresser.delay + 1.5)
}
