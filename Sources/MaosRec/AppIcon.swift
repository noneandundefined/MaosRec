import AppKit

enum AppIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 512, height: 512))
        image.lockFocus()

        let background = NSBezierPath(
            roundedRect: NSRect(x: 28, y: 28, width: 456, height: 456),
            xRadius: 105,
            yRadius: 105
        )
        NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.075, alpha: 1).setFill()
        background.fill()

        let center = NSPoint(x: 256, y: 256)
        let radius: CGFloat = 131

        for index in 0..<3 {
            let angle = CGFloat(index) * (2 * .pi / 3) - .pi / 2
            petal(center: center, radius: radius, angle: angle).fill()
        }

        NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.075, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 207, y: 207, width: 98, height: 98)).fill()

        NSColor(calibratedRed: 0.95, green: 0.18, blue: 0.20, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 234, y: 234, width: 44, height: 44)).fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func petal(center: NSPoint, radius: CGFloat, angle: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let inner = point(center: center, radius: radius * 0.24, angle: angle + .pi)
        let tip = point(center: center, radius: radius, angle: angle)
        let c1 = point(center: center, radius: radius * 0.92, angle: angle - .pi / 3)
        let c2 = point(center: center, radius: radius * 0.92, angle: angle + .pi / 3)
        let innerControl1 = point(center: center, radius: radius * 0.48, angle: angle - .pi / 2.5)
        let innerControl2 = point(center: center, radius: radius * 0.48, angle: angle + .pi / 2.5)

        path.move(to: inner)
        path.curve(to: tip, controlPoint1: innerControl1, controlPoint2: c1)
        path.curve(to: inner, controlPoint1: c2, controlPoint2: innerControl2)
        path.close()

        NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
        return path
    }

    private static func point(center: NSPoint, radius: CGFloat, angle: CGFloat) -> NSPoint {
        NSPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}
