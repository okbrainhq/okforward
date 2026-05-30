import AppKit

enum StatusIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
        }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        NSColor.black.setStroke()

        let lineWidth: CGFloat = 2.2

        // First chevron — centered
        let chevron1 = NSBezierPath()
        chevron1.lineWidth = lineWidth
        chevron1.lineCapStyle = .round
        chevron1.lineJoinStyle = .round
        chevron1.move(to: NSPoint(x: 4.5, y: 4))
        chevron1.line(to: NSPoint(x: 8, y: 9))
        chevron1.line(to: NSPoint(x: 4.5, y: 14))
        chevron1.stroke()

        // Second chevron — centered
        let chevron2 = NSBezierPath()
        chevron2.lineWidth = lineWidth
        chevron2.lineCapStyle = .round
        chevron2.lineJoinStyle = .round
        chevron2.move(to: NSPoint(x: 11, y: 4))
        chevron2.line(to: NSPoint(x: 14.5, y: 9))
        chevron2.line(to: NSPoint(x: 11, y: 14))
        chevron2.stroke()

        return image
    }
}
