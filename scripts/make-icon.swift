import AppKit

struct IconStyle {
    let name: String
    let background: NSColor
    let glyph: NSColor
    let bar: NSColor
}

let size: CGFloat = 1024
let rows = 22
let columns = rows * 2

func rings() -> [String] {
    let ramp: [Character] = Array(" .·:")
    let innerRadius = 0.3
    return (0..<rows).map { y in
        String((0..<columns).map { x in
            let nx = (Double(x) + 0.5) / Double(columns) * 2 - 1
            let ny = (Double(y) + 0.5) / Double(rows) * 2 - 1
            let distance = (nx * nx + ny * ny).squareRoot()
            guard distance >= innerRadius else { return " " }
            let ring = 0.5 + 0.5 * cos((distance - innerRadius) * .pi * 7)
            let fade = max(0, 1 - (distance - innerRadius) / 0.85)
            return ramp[min(3, Int(ring * fade * 3.99))]
        })
    }
}

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

    let lineHeight = size / CGFloat(rows)
    let font = NSFont.monospacedSystemFont(ofSize: size / (CGFloat(columns) * 0.6), weight: .regular)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.glyph]
    for (index, line) in rings().enumerated() {
        let text = NSAttributedString(string: line, attributes: attributes)
        let bounds = text.size()
        let y = size - (CGFloat(index) + 0.5) * lineHeight - bounds.height / 2
        text.draw(at: NSPoint(x: (size - bounds.width) / 2, y: y))
    }

    let barWidth = size * 0.075
    let barHeight = size * 0.34
    let bar = NSBezierPath(
        roundedRect: NSRect(x: (size - barWidth) / 2, y: (size - barHeight) / 2, width: barWidth, height: barHeight),
        xRadius: barWidth / 2, yRadius: barWidth / 2
    )
    style.bar.setFill()
    bar.fill()

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
    IconStyle(name: "icon", background: color(0x000000), glyph: color(0x5A5A60), bar: color(0xF4F4F1)),
    IconStyle(name: "icon-dark", background: color(0x000000), glyph: color(0x5A5A60), bar: color(0xF4F4F1)),
    IconStyle(name: "icon-tinted", background: color(0x000000), glyph: color(0x6A6A6A), bar: color(0xFFFFFF))
]

do {
    for style in styles {
        try render(style, into: directory)
    }
} catch {
    print("Failed: \(error)")
    exit(1)
}
