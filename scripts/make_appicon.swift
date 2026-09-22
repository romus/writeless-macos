#!/usr/bin/env swift
// Renders Assets.xcassets/AppIcon.appiconset from the design's icon component
// (WritelessIcon.dc.html): a rounded tile with a microphone capsule that reads
// equally as a text cursor, over the baseline of a line of text. No wordmark —
// the system shows the app's name.
//
//   swift scripts/make_appicon.swift [--skin graphite|paper|blue]
import AppKit

// MARK: - Design values

struct Skin {
    /// 165° linear gradient stops, as in the design.
    let background: [(location: CGFloat, color: NSColor)]
    let mark: NSColor
}

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

let skins: [String: Skin] = [
    "graphite": Skin(
        background: [(0, rgb(0x4C4C54)), (0.58, rgb(0x2A2A30)), (1, rgb(0x1D1D21))],
        mark: .white
    ),
    "paper": Skin(
        background: [(0, rgb(0xFBFBFD)), (0.60, rgb(0xE9E8EE)), (1, rgb(0xDCDBE3))],
        mark: rgb(0x1C1C1E)
    ),
    "blue": Skin(
        background: [(0, rgb(0x58A6FF)), (0.55, rgb(0x0A84FF)), (1, rgb(0x0060DF))],
        mark: .white
    ),
]

// The tile fills 824 of the 1024 pt canvas, Apple's proportion for macOS icons.
let tileRatio: CGFloat = 824.0 / 1024.0
let cornerRatio: CGFloat = 0.2237
let glyphRatio: CGFloat = 0.62

// MARK: - Drawing

func drawIcon(size: CGFloat, skin: Skin, into context: CGContext) {
    let tileSide = size * tileRatio
    let tile = CGRect(
        x: (size - tileSide) / 2,
        y: (size - tileSide) / 2,
        width: tileSide,
        height: tileSide
    )
    let radius = tileSide * cornerRatio
    let tilePath = CGPath(
        roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil
    )

    // Soft shadow under the tile, the way macOS icons carry their own.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -tileSide * 0.03),
        blur: tileSide * 0.08,
        color: NSColor.black.withAlphaComponent(0.30).cgColor
    )
    context.addPath(tilePath)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    // Background: CSS `linear-gradient(165deg, …)`, i.e. mostly downwards.
    let angle = 165.0 * CGFloat.pi / 180
    let direction = CGPoint(x: sin(angle), y: -cos(angle)) // y up
    let length = tileSide * (abs(sin(angle)) + abs(cos(angle)))
    let centre = CGPoint(x: tile.midX, y: tile.midY)
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: skin.background.map(\.color.cgColor) as CFArray,
        locations: skin.background.map(\.location)
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(
            x: centre.x - direction.x * length / 2,
            y: centre.y - direction.y * length / 2
        ),
        end: CGPoint(
            x: centre.x + direction.x * length / 2,
            y: centre.y + direction.y * length / 2
        ),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Gloss: white 28% at the top, gone by 42% down.
    let gloss = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor.white.withAlphaComponent(0.28).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gloss,
        start: CGPoint(x: tile.midX, y: tile.maxY),
        end: CGPoint(x: tile.midX, y: tile.maxY - tileSide * 0.42),
        options: [.drawsAfterEndLocation]
    )

    // Hairlines: a light edge along the top, a dark one all round.
    let hairline = max(1, tileSide * (0.5 / 160))
    context.setFillColor(NSColor.white.withAlphaComponent(0.45).cgColor)
    context.fill(CGRect(x: tile.minX, y: tile.maxY - hairline, width: tile.width, height: hairline))
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.setLineWidth(hairline)
    context.setStrokeColor(NSColor.black.withAlphaComponent(0.12).cgColor)
    context.strokePath()
    context.restoreGState()

    drawGlyph(in: tile, side: tileSide, mark: skin.mark, into: context)
}

/// The glyph, in the design's 100×100 viewBox.
func drawGlyph(in tile: CGRect, side: CGFloat, mark: NSColor, into context: CGContext) {
    let glyphSide = side * glyphRatio
    let glyph = CGRect(
        x: tile.midX - glyphSide / 2,
        y: tile.midY - glyphSide / 2,
        width: glyphSide,
        height: glyphSide
    )

    context.saveGState()
    // Flip into SVG coordinates (y down) so the paths read like the source.
    context.translateBy(x: glyph.minX, y: glyph.maxY)
    context.scaleBy(x: glyphSide / 100, y: -glyphSide / 100)
    context.setLineCap(.round)

    // The capsule: microphone body and text cursor at once.
    context.addPath(CGPath(
        roundedRect: CGRect(x: 43.5, y: 20, width: 13, height: 40),
        cornerWidth: 6.5, cornerHeight: 6.5, transform: nil
    ))
    context.setFillColor(mark.cgColor)
    context.fillPath()

    // Two faint ticks either side.
    context.setStrokeColor(mark.withAlphaComponent(0.38).cgColor)
    context.setLineWidth(5)
    context.move(to: CGPoint(x: 30, y: 26))
    context.addLine(to: CGPoint(x: 30, y: 34))
    context.move(to: CGPoint(x: 70, y: 26))
    context.addLine(to: CGPoint(x: 70, y: 34))
    context.strokePath()

    context.setStrokeColor(mark.cgColor)
    context.setLineWidth(5.5)

    // The cradle: a half circle under the capsule.
    context.addArc(
        center: CGPoint(x: 50, y: 50), radius: 28,
        startAngle: .pi, endAngle: 0, clockwise: true
    )
    context.strokePath()

    // The baseline of a line of text.
    context.move(to: CGPoint(x: 32, y: 80))
    context.addLine(to: CGPoint(x: 68, y: 80))
    context.strokePath()

    context.restoreGState()
}

func renderPNG(size: Int, skin: Skin) -> Data {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    let graphicsContext = NSGraphicsContext(bitmapImageRep: representation)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    drawIcon(size: CGFloat(size), skin: skin, into: graphicsContext.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    return representation.representation(using: .png, properties: [:])!
}

// MARK: - Output

let arguments = CommandLine.arguments
var skinName = "graphite"
if let flag = arguments.firstIndex(of: "--skin"), arguments.index(after: flag) < arguments.endIndex {
    skinName = arguments[arguments.index(after: flag)]
}
guard let skin = skins[skinName] else {
    FileHandle.standardError.write(Data("Unknown skin '\(skinName)'. Use graphite, paper or blue.\n".utf8))
    exit(1)
}

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appending(path: "Writeless/Resources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Each macOS icon size, at 1× and 2×.
let entries: [(point: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

var images: [String] = []
for entry in entries {
    let suffix = entry.scale == 1 ? "" : "@\(entry.scale)x"
    let name = "icon_\(entry.point)x\(entry.point)\(suffix).png"
    try renderPNG(size: entry.point * entry.scale, skin: skin).write(to: iconset.appending(path: name))
    images.append("""
        { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(entry.scale)x", "size" : "\(entry.point)x\(entry.point)" }
    """)
}

let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try Data(contents.utf8).write(to: iconset.appending(path: "Contents.json"))
print("Rendered the \(skinName) icon into \(iconset.path)")
