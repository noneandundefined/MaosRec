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

func writeIcon(size: Int, to url: URL) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space, bitmapInfo: info) else { throw IconError.context }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    let d = CGFloat(size)
    let background = CGPath(roundedRect: CGRect(x: d * 0.045, y: d * 0.045, width: d * 0.91, height: d * 0.91), cornerWidth: d * 0.22, cornerHeight: d * 0.22, transform: nil)
    context.addPath(background)
    context.setFillColor(color(0.06, 0.08, 0.12, space: space))
    context.fillPath()

    context.setStrokeColor(color(0.20, 0.55, 0.98, space: space))
    context.setLineWidth(d * 0.085)
    context.strokeEllipse(in: CGRect(x: d * 0.22, y: d * 0.22, width: d * 0.56, height: d * 0.56))
    context.setFillColor(color(0.96, 0.97, 1.0, space: space))
    context.fillEllipse(in: CGRect(x: d * 0.39, y: d * 0.39, width: d * 0.22, height: d * 0.22))
    context.setFillColor(color(0.96, 0.24, 0.28, space: space))
    context.fillEllipse(in: CGRect(x: d * 0.69, y: d * 0.69, width: d * 0.11, height: d * 0.11))

    guard let image = context.makeImage() else { throw IconError.image }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw IconError.destination }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.write }
}

do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, size) in variants { try writeIcon(size: size, to: output.appendingPathComponent(name)) }
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
