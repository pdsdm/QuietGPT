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
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
    ) else { throw CocoaError(.fileWriteUnknown) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    style.background.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let pattern = [".XXX.", "X...X", "XXXXX", "XX.XX", "XXXXX"]
    let side = size * 0.5
    let cell = side / CGFloat(pattern.count)
    let inset = cell * 0.05
    let left = (size - side) / 2
    let top = (size + side) / 2
    style.mark.setFill()
    for (row, line) in pattern.enumerated() {
        for (column, character) in line.enumerated() where character == "X" {
            NSRect(
                x: left + CGFloat(column) * cell + inset,
                y: top - CGFloat(row + 1) * cell + inset,
                width: cell - inset * 2,
                height: cell - inset * 2
            ).fill()
        }
    }

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
