import AppKit
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift make-icon.swift /path/to/CursorHalo.iconset /path/to/CursorHalo.icns\n", stderr)
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "CursorHalo.Icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Unable to create icon bitmap."])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -15)
    shadow.set()
    NSColor(srgbRed: 0.10, green: 0.15, blue: 0.22, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.18, green: 0.25, blue: 0.34, alpha: 1),
                              ending: NSColor(srgbRed: 0.07, green: 0.11, blue: 0.18, alpha: 1))!
    gradient.draw(in: tile, angle: -90)

    let ring = NSBezierPath(ovalIn: NSRect(x: 267, y: 279, width: 490, height: 490))
    NSColor(srgbRed: 1, green: 0.75, blue: 0.18, alpha: 0.12).setFill()
    ring.fill()
    NSColor(srgbRed: 1, green: 0.75, blue: 0.18, alpha: 1).setStroke()
    ring.lineWidth = 53
    ring.stroke()

    let pointer = NSBezierPath()
    pointer.move(to: NSPoint(x: 423, y: 665))
    pointer.line(to: NSPoint(x: 423, y: 352))
    pointer.line(to: NSPoint(x: 501, y: 428))
    pointer.line(to: NSPoint(x: 558, y: 299))
    pointer.line(to: NSPoint(x: 624, y: 329))
    pointer.line(to: NSPoint(x: 567, y: 456))
    pointer.line(to: NSPoint(x: 672, y: 456))
    pointer.close()
    NSColor(srgbRed: 0.07, green: 0.11, blue: 0.18, alpha: 1).setStroke()
    pointer.lineWidth = 25
    pointer.lineJoinStyle = .round
    pointer.stroke()
    NSColor.white.setFill()
    pointer.fill()
    context.flushGraphics()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CursorHalo.Icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Unable to encode icon PNG."])
    }
    return png
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let filename = "icon_\(size)x\(size)\(suffix).png"
        try renderIcon(pixels: size * scale).write(to: output.appendingPathComponent(filename))
    }
}

// ICNS is a length-prefixed family of typed image chunks. Writing PNG chunks
// directly avoids an iconutil encoder subprocess; ImageIO validates every slice.
let slices: [(String, String)] = [
    ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")
]
func bigEndianLength(_ value: Int) -> Data {
    var length = UInt32(value).bigEndian
    return withUnsafeBytes(of: &length) { Data($0) }
}
var payload = Data()
for (type, filename) in slices {
    let png = try Data(contentsOf: output.appendingPathComponent(filename))
    payload.append(Data(type.utf8))
    payload.append(bigEndianLength(png.count + 8))
    payload.append(png)
}
var family = Data("icns".utf8)
family.append(bigEndianLength(payload.count + 8))
family.append(payload)
let iconURL = URL(fileURLWithPath: CommandLine.arguments[2])
try family.write(to: iconURL, options: .atomic)
guard let source = CGImageSourceCreateWithURL(iconURL as CFURL, nil),
      CGImageSourceGetCount(source) == slices.count,
      (0..<slices.count).allSatisfy({ CGImageSourceCreateImageAtIndex(source, $0, nil) != nil }) else {
    throw NSError(domain: "CursorHalo.Icon", code: 3,
                  userInfo: [NSLocalizedDescriptionKey: "Generated ICNS failed ImageIO validation."])
}
