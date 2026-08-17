//
//  render-dev-ribbon.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// dev 版アイコン（AppIconDev.icon）に重ねる「DEV」リボンの SVG を書き出す。
//
// 文字は <text> ではなくアウトライン（パス）で出す。Icon Composer の SVG は
// フォント解決を当てにできないうえ、環境によって字形がずれると「同じアイコンの
// はずが違って見える」事故になる。帯はアイコンのマスクからはみ出す大きさで描き、
// 角丸の切り取りは Icon Composer 側に任せる。
//
//   swift scripts/render-dev-ribbon.swift Thaw/Resources/AppIconDev.icon/Assets/dev-ribbon.svg

import AppKit

guard CommandLine.arguments.count == 2 else {
    print("usage: render-dev-ribbon.swift <出力する .svg のパス>")
    exit(1)
}
let outURL = URL(fileURLWithPath: CommandLine.arguments[1])

// アイコンのキャンバスは 1024pt 四方。帯は反対角線（x + y = const）に平行に置く。
let canvas: CGFloat = 1024
let nearEdge: CGFloat = 1424 // 帯の内側の縁（中心に近い側）
let farEdge: CGFloat = 1676 // 帯の外側の縁（右下の角に近い側）
let bandCenter = (nearEdge + farEdge) / 2
let bandColor = "#f5a623"
let textColor = "#3d2600"

// MARK: - 帯

// x + y = c の直線は c > 1024 ならキャンバスの外まで伸びる。4 隅を素直に置けば、
// 角丸マスクの外側まで確実に覆える。
let band = """
M \(nearEdge) 0 L 0 \(nearEdge) L 0 \(farEdge) L \(farEdge) 0 Z
"""

// MARK: - 文字

let text = "DEV"
let fontSize: CGFloat = 132
let tracking: CGFloat = 18
let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy) as CTFont

var characters = Array(text.utf16)
var glyphs = [CGGlyph](repeating: 0, count: characters.count)
guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) else {
    print("グリフを取得できない: \(text)")
    exit(1)
}
var advances = [CGSize](repeating: .zero, count: glyphs.count)
CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advances, glyphs.count)

let totalWidth = advances.reduce(0) { $0 + $1.width } + tracking * CGFloat(glyphs.count - 1)

// フォントは y 上向き。原点を文字列の中心（水平は幅の中央、垂直は cap height の
// 半分）に合わせてから、まとめて回転・移動させる。
let letters = CGMutablePath()
var penX = -totalWidth / 2
let baselineOffset = -CTFontGetCapHeight(font) / 2
for (index, glyph) in glyphs.enumerated() {
    if let glyphPath = CTFontCreatePathForGlyph(font, glyph, nil) {
        letters.addPath(glyphPath, transform: CGAffineTransform(translationX: penX, y: baselineOffset))
    }
    penX += advances[index].width + tracking
}

// SVG は y 下向きなので反転させ、帯に沿って -45° 回して帯の中心へ運ぶ。
let center = bandCenter / 2
var transform = CGAffineTransform(translationX: center, y: center)
    .rotated(by: -.pi / 4)
    .scaledBy(x: 1, y: -1)
guard let placedLetters = letters.copy(using: &transform) else {
    print("文字パスを変換できない")
    exit(1)
}

// MARK: - SVG 化

func svgPathData(_ path: CGPath) -> String {
    var data = ""
    func format(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
    path.applyWithBlock { elementPointer in
        let element = elementPointer.pointee
        let points = element.points
        switch element.type {
        case .moveToPoint:
            data += "M \(format(points[0].x)) \(format(points[0].y)) "
        case .addLineToPoint:
            data += "L \(format(points[0].x)) \(format(points[0].y)) "
        case .addQuadCurveToPoint:
            data += "Q \(format(points[0].x)) \(format(points[0].y)) "
                + "\(format(points[1].x)) \(format(points[1].y)) "
        case .addCurveToPoint:
            data += "C \(format(points[0].x)) \(format(points[0].y)) "
                + "\(format(points[1].x)) \(format(points[1].y)) "
                + "\(format(points[2].x)) \(format(points[2].y)) "
        case .closeSubpath:
            data += "Z "
        @unknown default:
            break
        }
    }
    return data.trimmingCharacters(in: .whitespaces)
}

let svg = """
<?xml version="1.0" encoding="UTF-8"?>
<svg width="\(Int(canvas))" height="\(Int(canvas))" viewBox="0 0 \(Int(canvas)) \(Int(canvas))" \
xmlns="http://www.w3.org/2000/svg">
    <g id="DevRibbon">
        <path id="Band" fill="\(bandColor)" fill-rule="evenodd" stroke="none" d="\(band)"/>
        <path id="Text" fill="\(textColor)" fill-rule="nonzero" stroke="none" d="\(svgPathData(placedLetters))"/>
    </g>
</svg>

"""

try! svg.write(to: outURL, atomically: true, encoding: .utf8)
print("書き出した: \(outURL.path)")
