// Draws Metro Network's app icon with Core Graphics (original vector art, no third-party assets) and writes
// MetroNetwork/Resources/Assets.xcassets/AppIcon.appiconset (every macOS size plus the iOS 1024 icon) and the
// menu logo (Logo.imageset).
// Run: swift Tools/make-icon.swift   (from the project root)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Draws the artwork into a square of side `s` (origin bottom-left).
func drawArt(_ ctx: CGContext, side s: CGFloat) {
    // Land with a faint street grid and a few city blocks.
    ctx.setFillColor(rgb(0xF5F2EA)); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    ctx.setFillColor(rgb(0xECE6DA))
    let cell = s / 8
    for (c, r) in [(0, 6), (1, 6), (5, 7), (6, 6), (0, 2), (6, 1), (7, 2), (2, 0), (5, 3), (1, 4)] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: CGFloat(c) * cell + cell * 0.12, y: CGFloat(r) * cell + cell * 0.12,
                                               width: cell * 0.76, height: cell * 0.76),
                           cornerWidth: cell * 0.08, cornerHeight: cell * 0.08, transform: nil))
    }
    ctx.fillPath()
    // A river along the bottom.
    ctx.setFillColor(rgb(0xA8D3EE))
    ctx.move(to: CGPoint(x: 0, y: s * 0.10))
    ctx.addCurve(to: CGPoint(x: s, y: s * 0.22), control1: CGPoint(x: s * 0.35, y: s * 0.24),
                 control2: CGPoint(x: s * 0.62, y: s * 0.04))
    ctx.addLine(to: CGPoint(x: s, y: 0)); ctx.addLine(to: CGPoint(x: 0, y: 0)); ctx.fillPath()

    // Three octilinear lines with rounded corners.
    func line(_ pts: [CGPoint], _ color: CGColor) {
        let w = s * 0.085
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let path = CGMutablePath()
        path.move(to: pts[0])
        for i in 1..<(pts.count - 1) { path.addArc(tangent1End: pts[i], tangent2End: pts[i + 1], radius: s * 0.08) }
        path.addLine(to: pts[pts.count - 1])
        ctx.addPath(path); ctx.setStrokeColor(rgb(0x000000, 0.18)); ctx.setLineWidth(w + s * 0.012); ctx.strokePath()
        ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(w); ctx.strokePath()
    }
    let hub = CGPoint(x: s * 0.50, y: s * 0.52)
    line([CGPoint(x: -s * 0.1, y: s * 0.52), hub, CGPoint(x: s * 0.70, y: s * 0.72), CGPoint(x: s * 1.1, y: s * 0.72)], rgb(0xE5484D))
    line([CGPoint(x: s * 0.30, y: s * 1.1), CGPoint(x: s * 0.30, y: s * 0.72), hub, CGPoint(x: s * 0.50, y: s * 0.30), CGPoint(x: s * 0.72, y: s * 0.08)], rgb(0x2F80ED))
    line([CGPoint(x: s * 1.1, y: s * 0.40), CGPoint(x: s * 0.62, y: s * 0.40), hub], rgb(0xF0A020))

    // Stations: an interchange at the hub, plus a triangle and a square.
    func stationStroke() { ctx.setStrokeColor(rgb(0x2A2F3A)); ctx.setLineWidth(s * 0.03); ctx.setFillColor(rgb(0xFFFFFF)) }
    stationStroke()
    let r = s * 0.075
    ctx.addEllipse(in: CGRect(x: hub.x - r, y: hub.y - r, width: 2 * r, height: 2 * r)); ctx.drawPath(using: .fillStroke)
    let t = CGPoint(x: s * 0.30, y: s * 0.72), tr = s * 0.07
    ctx.move(to: CGPoint(x: t.x, y: t.y + tr * 1.1))
    ctx.addLine(to: CGPoint(x: t.x - tr, y: t.y - tr * 0.65)); ctx.addLine(to: CGPoint(x: t.x + tr, y: t.y - tr * 0.65))
    ctx.closePath(); ctx.drawPath(using: .fillStroke)
    let q = CGPoint(x: s * 0.70, y: s * 0.72), qr = s * 0.058
    ctx.addPath(CGPath(roundedRect: CGRect(x: q.x - qr, y: q.y - qr, width: 2 * qr, height: 2 * qr),
                       cornerWidth: s * 0.01, cornerHeight: s * 0.01, transform: nil))
    ctx.drawPath(using: .fillStroke)
}

func render(side: Int, macStyle: Bool) -> CGImage {
    let s = CGFloat(side)
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: macStyle ? CGImageAlphaInfo.premultipliedLast.rawValue
                                             : CGImageAlphaInfo.noneSkipLast.rawValue)!
    if macStyle {
        // macOS icon grid: 824/1024 rounded square with a soft shadow.
        let inset = s * 100 / 1024, side = s * 824 / 1024
        let rect = CGRect(x: inset, y: inset + s * 0.01, width: side, height: side)
        let shape = CGPath(roundedRect: rect, cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: rgb(0x000000, 0.3))
        ctx.addPath(shape); ctx.setFillColor(rgb(0xF5F2EA)); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(shape); ctx.clip()
        ctx.translateBy(x: inset, y: inset + s * 0.01)
        drawArt(ctx, side: side)
    } else {
        drawArt(ctx, side: s)
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let dir = URL(fileURLWithPath: "MetroNetwork/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "mac-\(points)@\(scale)x.png"
        write(render(side: points * scale, macStyle: true), to: dir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
write(render(side: 1024, macStyle: false), to: dir.appendingPathComponent("ios-1024.png"))
images.append(["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "ios-1024.png"])
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: dir.appendingPathComponent("Contents.json"))
// The same artwork as an in-app logo (macOS-style rounded square with transparent corners).
let logoDir = URL(fileURLWithPath: "MetroNetwork/Resources/Assets.xcassets/Logo.imageset")
try FileManager.default.createDirectory(at: logoDir, withIntermediateDirectories: true)
write(render(side: 512, macStyle: true), to: logoDir.appendingPathComponent("logo.png"))
try #"{ "images" : [ { "filename" : "logo.png", "idiom" : "universal" } ], "info" : { "author" : "xcode", "version" : 1 } }"#
    .write(to: logoDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
let catalog = URL(fileURLWithPath: "MetroNetwork/Resources/Assets.xcassets/Contents.json")
try #"{ "info" : { "author" : "xcode", "version" : 1 } }"#.write(to: catalog, atomically: true, encoding: .utf8)
print("Wrote \(images.count) icons to \(dir.path)")
