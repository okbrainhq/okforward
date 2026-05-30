import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: NSSize(width: size, height: size)).fill()

    let scale = size / 18.0
    let lineWidth: CGFloat = 2.2 * scale
    let strokeColor = NSColor.black

    strokeColor.setStroke()

    let chevron1 = NSBezierPath()
    chevron1.lineWidth = lineWidth
    chevron1.lineCapStyle = .round
    chevron1.lineJoinStyle = .round
    chevron1.move(to: NSPoint(x: 4.5 * scale, y: 4 * scale))
    chevron1.line(to: NSPoint(x: 8 * scale, y: 9 * scale))
    chevron1.line(to: NSPoint(x: 4.5 * scale, y: 14 * scale))
    chevron1.stroke()

    let chevron2 = NSBezierPath()
    chevron2.lineWidth = lineWidth
    chevron2.lineCapStyle = .round
    chevron2.lineJoinStyle = .round
    chevron2.move(to: NSPoint(x: 11 * scale, y: 4 * scale))
    chevron2.line(to: NSPoint(x: 14.5 * scale, y: 9 * scale))
    chevron2.line(to: NSPoint(x: 11 * scale, y: 14 * scale))
    chevron2.stroke()

    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to generate PNG")
    }
    try! data.write(to: URL(fileURLWithPath: path))
}

let sizes: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

for item in sizes {
    let img = drawIcon(size: item.size)
    let path = "\(outDir)/\(item.name).png"
    savePNG(img, to: path)
    print("Generated \(path)")
}
