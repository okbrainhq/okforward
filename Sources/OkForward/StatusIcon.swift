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
        NSColor.black.setFill()

        drawLane(y: 5.5)
        drawLane(y: 12.5)

        return image
    }

    private static func drawLane(y: CGFloat) {
        let arrow = NSBezierPath()
        arrow.lineWidth = 1.8
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(x: 4.3, y: y))
        arrow.line(to: NSPoint(x: 12.3, y: y))
        arrow.move(to: NSPoint(x: 9.8, y: y - 2.3))
        arrow.line(to: NSPoint(x: 12.5, y: y))
        arrow.line(to: NSPoint(x: 9.8, y: y + 2.3))
        arrow.stroke()

        NSBezierPath(ovalIn: NSRect(x: 3, y: y - 1.3, width: 2.6, height: 2.6)).fill()
        NSBezierPath(ovalIn: NSRect(x: 13, y: y - 1.3, width: 2.6, height: 2.6)).fill()
    }
}
