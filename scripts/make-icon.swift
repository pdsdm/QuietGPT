import AppKit

struct IconStyle {
    let name: String
    let background: NSColor
    let lips: NSColor
    let finger: NSColor
}

let size: CGFloat = 1024

func render(_ style: IconStyle, into directory: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw CocoaError(.fileWriteUnknown) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let unit = size / 100
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: x * unit, y: size - y * unit)
    }

    style.background.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let start = point(27, 57)
    let control = point(50, 69)
    let end = point(73, 57)
    let lips = NSBezierPath()
    lips.move(to: start)
    lips.curve(
        to: end,
        controlPoint1: NSPoint(x: start.x + (control.x - start.x) * 2 / 3, y: start.y + (control.y - start.y) * 2 / 3),
        controlPoint2: NSPoint(x: end.x + (control.x - end.x) * 2 / 3, y: end.y + (control.y - end.y) * 2 / 3)
    )
    lips.lineWidth = 6 * unit
    lips.lineCapStyle = .round
    style.lips.setStroke()
    lips.stroke()

    let fingerWidth = 7.5 * unit
    let finger = NSBezierPath(
        roundedRect: NSRect(x: 46.25 * unit, y: size - 74 * unit, width: fingerWidth, height: 52 * unit),
        xRadius: fingerWidth / 2, yRadius: fingerWidth / 2
    )
    style.finger.setFill()
    finger.fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: directory.appendingPathComponent("\(style.name).png"))
}

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("Usage: swift scripts/make-icon.swift <AppIcon.appiconset>")
    exit(1)
}
let directory = URL(fileURLWithPath: arguments[1])

let styles = [
    IconStyle(name: "icon", background: color(0x000000), lips: color(0x7CC4FF), finger: color(0xF4F4F1)),
    IconStyle(name: "icon-dark", background: color(0x000000), lips: color(0x7CC4FF), finger: color(0xF4F4F1)),
    IconStyle(name: "icon-tinted", background: color(0x000000), lips: color(0xBDBDBD), finger: color(0xFFFFFF))
]

do {
    for style in styles {
        try render(style, into: directory)
    }
} catch {
    print("Failed: \(error)")
    exit(1)
}
