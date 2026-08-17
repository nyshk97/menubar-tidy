//
//  render-status-icons.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// ビルド済みアプリの Assets.car から状態アイコンを読み、ControlItemImage.catalog
// と同じリサイズを通してから、メニューバー相当の黒地に白で 2x 描画する。
//
// アプリを起動せずに「メニューバーに実際に出る絵」を確認するための道具。
// 起動して目視すると権限が要るうえ、実メニューバーを掴んで作業中の環境を壊す。
//
//   swift scripts/render-status-icons.swift \
//       "Build/Build/Products/Debug/MenuBar Tidy.app" /tmp/icons

import AppKit

guard CommandLine.arguments.count == 3 else {
    print("usage: render-status-icons.swift <.app のパス> <出力ディレクトリ>")
    exit(1)
}

let appPath = CommandLine.arguments[1]
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
guard let bundle = Bundle(url: URL(fileURLWithPath: appPath)) else {
    print("バンドルを開けない: \(appPath)")
    exit(1)
}

for name in ["TidyBarFill", "TidyBarStroke"] {
    guard let original = bundle.image(forResource: name) else {
        print("\(name): アセットが読めない"); exit(1)
    }
    // ControlItemImage.catalog と同じ計算。
    let ratio = max(original.size.width / 25, original.size.height / 17)
    let newSize = CGSize(width: original.size.width / ratio, height: original.size.height / ratio)
    print("\(name): 元 \(original.size.width)x\(original.size.height)pt → \(newSize.width)x\(newSize.height)pt (ratio \(ratio))")

    // 実機のメニューバー（黒地・テンプレートは白で描かれる）を模した 2x 画像。
    let scale: CGFloat = 2
    let barSize = CGSize(width: 40, height: 34)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(barSize.width * scale), pixelsHigh: Int(barSize.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = barSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    CGRect(origin: .zero, size: barSize).fill()
    let target = CGRect(
        x: (barSize.width - newSize.width) / 2,
        y: (barSize.height - newSize.height) / 2,
        width: newSize.width, height: newSize.height
    )
    // アセットは黒のテンプレート画像。白地に描いてから全体を反転すると、
    // メニューバー（暗い背景に白で描かれる）と同じ見え方になる。
    original.draw(in: target)
    NSGraphicsContext.restoreGraphicsState()

    let bytes = rep.bitmapData!
    for i in stride(from: 0, to: rep.pixelsHigh * rep.bytesPerRow, by: 4) {
        bytes[i] = 255 &- bytes[i]
        bytes[i + 1] = 255 &- bytes[i + 1]
        bytes[i + 2] = 255 &- bytes[i + 2]
    }

    try rep.representation(using: .png, properties: [:])!
        .write(to: outDir.appendingPathComponent("rendered-\(name).png"))
}

print("ok")
