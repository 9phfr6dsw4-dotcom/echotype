import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: create-app-icon.swift <iconset-directory>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int, fileName: String) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "EchoTypeIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create icon bitmap"])
    }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "EchoTypeIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create icon graphics context"])
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(pixelSize) / 1024, y: CGFloat(pixelSize) / 1024)

    NSColor(calibratedRed: 0.055, green: 0.085, blue: 0.15, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 220, yRadius: 220).fill()

    let waveform = NSBezierPath()
    waveform.lineWidth = 58
    waveform.lineCapStyle = .round
    waveform.lineJoinStyle = .round
    waveform.move(to: NSPoint(x: 160, y: 512))
    waveform.line(to: NSPoint(x: 292, y: 512))
    waveform.line(to: NSPoint(x: 390, y: 300))
    waveform.line(to: NSPoint(x: 492, y: 730))
    waveform.line(to: NSPoint(x: 616, y: 360))
    waveform.line(to: NSPoint(x: 710, y: 575))
    waveform.line(to: NSPoint(x: 864, y: 575))
    NSColor(calibratedRed: 0.34, green: 0.78, blue: 1, alpha: 1).setStroke()
    waveform.stroke()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "EchoTypeIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"])
    }
    try data.write(to: iconsetURL.appendingPathComponent(fileName), options: .atomic)
}

let icons: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]
for (size, name) in icons {
    try renderIcon(pixelSize: size, fileName: name)
}
