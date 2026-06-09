import AppKit

enum StatusIcon {
    static var tasktarrasque: NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setStroke()
        NSColor.black.setFill()

        // A tiny tarrasque head: horns, ears, eyes, snout, and teeth. It stays
        // template-compatible so macOS can tint it like a normal menu bar item.
        let leftHorn = NSBezierPath()
        leftHorn.move(to: NSPoint(x: 5.0, y: 13.0))
        leftHorn.line(to: NSPoint(x: 3.0, y: 17.0))
        leftHorn.line(to: NSPoint(x: 7.0, y: 14.2))
        leftHorn.close()
        leftHorn.fill()

        let rightHorn = NSBezierPath()
        rightHorn.move(to: NSPoint(x: 13.0, y: 13.0))
        rightHorn.line(to: NSPoint(x: 15.0, y: 17.0))
        rightHorn.line(to: NSPoint(x: 11.0, y: 14.2))
        rightHorn.close()
        rightHorn.fill()

        let head = NSBezierPath(roundedRect: NSRect(x: 3.0, y: 3.0, width: 12.0, height: 12.0), xRadius: 4.0, yRadius: 4.0)
        head.lineWidth = 1.4
        head.stroke()

        let leftEar = NSBezierPath()
        leftEar.move(to: NSPoint(x: 3.5, y: 11.5))
        leftEar.line(to: NSPoint(x: 1.7, y: 10.2))
        leftEar.line(to: NSPoint(x: 3.3, y: 8.9))
        leftEar.lineWidth = 1.2
        leftEar.stroke()

        let rightEar = NSBezierPath()
        rightEar.move(to: NSPoint(x: 14.5, y: 11.5))
        rightEar.line(to: NSPoint(x: 16.3, y: 10.2))
        rightEar.line(to: NSPoint(x: 14.7, y: 8.9))
        rightEar.lineWidth = 1.2
        rightEar.stroke()

        NSBezierPath(ovalIn: NSRect(x: 6.0, y: 9.4, width: 1.8, height: 1.8)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.2, y: 9.4, width: 1.8, height: 1.8)).fill()

        let snout = NSBezierPath(roundedRect: NSRect(x: 6.0, y: 5.2, width: 6.0, height: 3.4), xRadius: 1.6, yRadius: 1.6)
        snout.lineWidth = 1.1
        snout.stroke()

        drawLine(from: NSPoint(x: 7.8, y: 6.7), to: NSPoint(x: 7.8, y: 6.7), width: 1.2)
        drawLine(from: NSPoint(x: 10.2, y: 6.7), to: NSPoint(x: 10.2, y: 6.7), width: 1.2)

        drawTooth(x: 6.2)
        drawTooth(x: 8.6)
        drawTooth(x: 11.0)

        image.isTemplate = true
        image.accessibilityDescription = "Tasktarrasque"
        return image
    }

    private static func drawTooth(x: CGFloat) {
        let tooth = NSBezierPath()
        tooth.move(to: NSPoint(x: x, y: 3.6))
        tooth.line(to: NSPoint(x: x + 0.8, y: 2.2))
        tooth.line(to: NSPoint(x: x + 1.6, y: 3.6))
        tooth.lineWidth = 0.9
        tooth.stroke()
    }

    private static func drawLine(from start: NSPoint, to end: NSPoint, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineCapStyle = .round
        path.lineWidth = width
        path.stroke()
    }
}
