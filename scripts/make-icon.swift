import AppKit

struct IconStyle {
    let name: String
    let background: NSColor
    let mark: NSColor
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

    style.background.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let side = size * 0.6
    let center = NSPoint(x: size / 2, y: size / 2)
    let burst = NSBezierPath()
    for ray in 0..<8 {
        let angle = Double.pi / 2 - Double(ray) * Double.pi / 4
        let direction = NSPoint(x: cos(angle), y: sin(angle))
        burst.move(to: NSPoint(x: center.x + direction.x * side * 23 / 120, y: center.y + direction.y * side * 23 / 120))
        burst.line(to: NSPoint(x: center.x + direction.x * side * 49 / 120, y: center.y + direction.y * side * 49 / 120))
    }
    burst.lineWidth = side * 10 / 120
    burst.lineCapStyle = .round
    style.mark.setStroke()
    burst.stroke()

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
    IconStyle(name: "icon", background: color(0xFFFFFF), mark: color(0x0A0A0A)),
    IconStyle(name: "icon-dark", background: color(0x000000), mark: color(0xFFFFFF)),
    IconStyle(name: "icon-tinted", background: color(0x000000), mark: color(0xFFFFFF))
]

do {
    for style in styles {
        try render(style, into: directory)
    }
} catch {
    print("Failed: \(error)")
    exit(1)
}
