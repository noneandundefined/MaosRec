import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_icon.swift <output.iconset>\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

enum IconError: Error { case context, image, destination, write }

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1, space: CGColorSpace) -> CGColor {
    CGColor(colorSpace: space, components: [red, green, blue, alpha])!
}

func petalPath(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let c1 = CGPoint(
        x: center.x + cos(angle - .pi / 3) * radius * 0.92,
        y: center.y + sin(angle - .pi / 3) * radius * 0.92
    )
    let c2 = CGPoint(
        x: center.x + cos(angle + .pi / 3) * radius * 0.92,
        y: center.y + sin(angle + .pi / 3) * radius * 0.92
    )
    let tip = CGPoint(
        x: center.x + cos(angle) * radius,
        y: center.y + sin(angle) * radius
    )
    let inner = CGPoint(
        x: center.x + cos(angle + .pi) * radius * 0.24,
        y: center.y + sin(angle + .pi) * radius * 0.24
    )

    path.move(to: inner)
    path.addCurve(
        to: tip,
        control1: CGPoint(
            x: center.x + cos(angle - .pi / 2.5) * radius * 0.48,
            y: center.y + sin(angle - .pi / 2.5) * radius * 0.48
        ),
        control2: c1
    )
    path.addCurve(
        to: inner,
        control1: c2,
        control2: CGPoint(
            x: center.x + cos(angle + .pi / 2.5) * radius * 0.48,
            y: center.y + sin(angle + .pi / 2.5) * radius * 0.48
        )
    )
    path.closeSubpath()
    return path
}

func writeIcon(size: Int, to url: URL) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: space,
        bitmapInfo: info
    ) else { throw IconError.context }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let d = CGFloat(size)
    let background = CGPath(
        roundedRect: CGRect(x: d * 0.055, y: d * 0.055, width: d * 0.89, height: d * 0.89),
        cornerWidth: d * 0.205,
        cornerHeight: d * 0.205,
        transform: nil
    )
    context.addPath(background)
    context.setFillColor(color(0.055, 0.06, 0.075, space: space))
    context.fillPath()

    let center = CGPoint(x: d * 0.5, y: d * 0.5)
    let radius = d * 0.255

    for index in 0..<3 {
        let angle = CGFloat(index) * (2 * .pi / 3) - .pi / 2
        context.addPath(petalPath(center: center, radius: radius, angle: angle))
        context.setFillColor(color(0.94, 0.95, 0.97, space: space))
        context.fillPath()
    }

    context.setFillColor(color(0.055, 0.06, 0.075, space: space))
    context.fillEllipse(in: CGRect(x: d * 0.405, y: d * 0.405, width: d * 0.19, height: d * 0.19))

    context.setFillColor(color(0.95, 0.18, 0.20, space: space))
    context.fillEllipse(in: CGRect(x: d * 0.4575, y: d * 0.4575, width: d * 0.085, height: d * 0.085))

    guard let image = context.makeImage() else { throw IconError.image }
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { throw IconError.destination }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.write }
}

do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, size) in variants {
        try writeIcon(size: size, to: output.appendingPathComponent(name))
    }
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
