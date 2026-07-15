// Draws the 1280x640 GitHub social preview (assets/social-preview.png).
// GitHub has no API for this image: upload manually in Settings → Social preview.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let width = 1280.0, height = 640.0
let ctx = CGContext(
    data: nil, width: Int(width), height: Int(height),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func deg(_ d: Double) -> Double { d * .pi / 180 }

// Background.
ctx.setFillColor(CGColor(red: 0.115, green: 0.115, blue: 0.125, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

// Gauge on the left (same design as the app icon).
let center = CGPoint(x: 320, y: height / 2 - 15)
let radius = 150.0
let startAngle = deg(210), endAngle = deg(-30)
let needleAngle = deg(210 - 0.62 * 240)

func strokeArc(from: Double, to: Double, color: CGColor, lineWidth: Double) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.addArc(center: center, radius: radius, startAngle: from, endAngle: to, clockwise: true)
    ctx.strokePath()
}

strokeArc(from: startAngle, to: endAngle, color: CGColor(gray: 1, alpha: 0.16), lineWidth: 38)
strokeArc(from: startAngle, to: needleAngle, color: CGColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1), lineWidth: 38)

let tip = CGPoint(x: center.x + cos(needleAngle) * radius * 0.72, y: center.y + sin(needleAngle) * radius * 0.72)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
ctx.setLineWidth(18)
ctx.setLineCap(.round)
ctx.beginPath()
ctx.move(to: center)
ctx.addLine(to: tip)
ctx.strokePath()
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fillEllipse(in: CGRect(x: center.x - 21, y: center.y - 21, width: 42, height: 42))

// Text on the right, drawn via AppKit on top of the CGContext.
let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = ns

func draw(_ string: String, at point: CGPoint, font: NSFont, color: NSColor) {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        .draw(at: point)
}

draw("Claudometer", at: CGPoint(x: 550, y: 360),
     font: .systemFont(ofSize: 84, weight: .bold), color: .white)
draw("Claude Code plan usage in your menu bar", at: CGPoint(x: 554, y: 296),
     font: .systemFont(ofSize: 30, weight: .regular), color: NSColor(white: 1, alpha: 0.65))
draw("5h 46% · 7d 12%", at: CGPoint(x: 554, y: 200),
     font: .monospacedSystemFont(ofSize: 40, weight: .medium),
     color: NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1))

NSGraphicsContext.current = nil

let image = ctx.makeImage()!
let out = URL(fileURLWithPath: "assets/social-preview.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
