import AppKit

enum AppIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 512, height: 512))
        image.lockFocus()

        let center = NSPoint(x: 256, y: 256)
        NSColor(srgbRed: 0.20, green: 0.21, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 18, y: 18, width: 476, height: 476)).fill()
        NSColor(srgbRed: 0.07, green: 0.075, blue: 0.08, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 42, y: 42, width: 428, height: 428)).fill()

        let bladeFill = NSGradient(colors: [
            NSColor(srgbRed: 0.78, green: 0.80, blue: 0.84, alpha: 1),
            NSColor(srgbRed: 0.97, green: 0.98, blue: 0.99, alpha: 1)
        ])
        let firstTip: CGFloat = -0.45
        for index in 0..<3 {
            let path = blade(center: center, tipAngle: firstTip + CGFloat(index) * 2 * .pi / 3)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            bladeFill?.draw(in: path.bounds, angle: 90)
            NSGraphicsContext.restoreGraphicsState()
        }

        NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 196, y: 196, width: 120, height: 120)).fill()

        let red = NSBezierPath(ovalIn: NSRect(x: 214, y: 214, width: 84, height: 84))
        NSGraphicsContext.saveGraphicsState()
        red.addClip()
        NSGradient(colors: [
            NSColor(srgbRed: 1, green: 0.55, blue: 0.45, alpha: 1),
            NSColor(srgbRed: 0.93, green: 0.08, blue: 0.06, alpha: 1),
            NSColor(srgbRed: 0.45, green: 0.02, blue: 0.03, alpha: 1)
        ])?.draw(
            fromCenter: NSPoint(x: 256, y: 268),
            radius: 2,
            toCenter: NSPoint(x: 256, y: 246),
            radius: 46,
            options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 1, alpha: 0.55).setFill()
        NSBezierPath(ovalIn: NSRect(x: 238, y: 262, width: 22, height: 12)).fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func blade(center: NSPoint, tipAngle: CGFloat) -> NSBezierPath {
        func at(_ radius: CGFloat, _ delta: CGFloat) -> NSPoint {
            let angle = tipAngle + delta
            return NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }

        let path = NSBezierPath()
        path.move(to: at(205, 0))
        path.curve(to: at(88, 1.9), controlPoint1: at(214, 0.72), controlPoint2: at(155, 1.55))
        path.curve(to: at(132, 1.18), controlPoint1: at(68, 1.55), controlPoint2: at(96, 1.12))
        path.curve(to: at(205, -0.02), controlPoint1: at(178, 0.62), controlPoint2: at(198, 0.22))
        path.close()
        return path
    }
}
