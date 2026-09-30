import AppKit

enum AppIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 512, height: 512))
        image.lockFocus()

        let background = NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 464, height: 464), xRadius: 104, yRadius: 104)
        NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.13, alpha: 1).setFill()
        background.fill()

        let lens = NSBezierPath(ovalIn: NSRect(x: 116, y: 116, width: 280, height: 280))
        NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.98, alpha: 1).setStroke()
        lens.lineWidth = 38
        lens.stroke()

        let inner = NSBezierPath(ovalIn: NSRect(x: 194, y: 194, width: 124, height: 124))
        NSColor.white.withAlphaComponent(0.94).setFill()
        inner.fill()

        let dot = NSBezierPath(ovalIn: NSRect(x: 356, y: 356, width: 52, height: 52))
        NSColor.systemRed.setFill()
        dot.fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
