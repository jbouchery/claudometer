// Draws the Claudometer app icon (a gauge) with CoreGraphics and writes icon_1024.png.
// Run via scripts/make-icon.sh, which turns it into AppIcon.icns.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func deg(_ d: Double) -> Double { d * .pi / 180 }

// Rounded-square plate, Big Sur proportions (~10% margin, ~22% corner radius).
let margin = size * 0.10
let plate = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let platePath = CGPath(roundedRect: plate, cornerWidth: plate.width * 0.2237, cornerHeight: plate.width * 0.2237, transform: nil)
ctx.addPath(platePath)
ctx.setFillColor(CGColor(red: 0.115, green: 0.115, blue: 0.125, alpha: 1))
ctx.fillPath()

// Gauge geometry: 240° sweep from 210° (bottom-left) to -30° (bottom-right).
let center = CGPoint(x: size / 2, y: size / 2 - size * 0.03)
let radius = plate.width * 0.30
let startAngle = deg(210), endAngle = deg(-30)
let needleAngle = deg(210 - 0.62 * 240)  // needle at 62% of the dial

func strokeArc(from: Double, to: Double, color: CGColor, width: Double) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.addArc(center: center, radius: radius, startAngle: from, endAngle: to, clockwise: true)
    ctx.strokePath()
}

// Track (full dial, faint) then progress (Claude coral, up to the needle).
strokeArc(from: startAngle, to: endAngle, color: CGColor(gray: 1, alpha: 0.16), width: size * 0.075)
strokeArc(from: startAngle, to: needleAngle, color: CGColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1), width: size * 0.075)

// Needle + hub.
let tip = CGPoint(x: center.x + cos(needleAngle) * radius * 0.72, y: center.y + sin(needleAngle) * radius * 0.72)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
ctx.setLineWidth(size * 0.035)
ctx.setLineCap(.round)
ctx.beginPath()
ctx.move(to: center)
ctx.addLine(to: tip)
ctx.strokePath()
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fillEllipse(in: CGRect(x: center.x - size * 0.042, y: center.y - size * 0.042, width: size * 0.084, height: size * 0.084))

let image = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
