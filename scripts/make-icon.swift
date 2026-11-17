import AppKit

// Draws Tuck's 1024px app icon. Usage: swift scripts/make-icon.swift <out.png>
let args = CommandLine.arguments
let variant = "dark"
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "icon.png")
let size: CGFloat = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func rounded(_ rect: CGRect, _ radius: CGFloat, _ color: CGColor, rotate: CGFloat = 0, shadow: Bool = false) {
    ctx.saveGState()
    ctx.translateBy(x: rect.midX, y: rect.midY)
    ctx.rotate(by: rotate * .pi / 180)
    if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: rgb(0x0B1E4A, 0.18)) }
    ctx.addPath(CGPath(roundedRect: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}

let dark = variant == "dark"
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.3))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let colors = dark ? [rgb(0x23314F), rgb(0x0E1626)] : [rgb(0xFFFFFF), rgb(0xE6ECF5)]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

let navy = rgb(0x1B3A8C), blue = rgb(0x2F6BFF), sky = rgb(0x8FB2FF)

switch variant {
case "menu":
    rounded(CGRect(x: 190, y: 700, width: 644, height: 96), 30, rgb(0x1B3A8C, 0.10))
    rounded(CGRect(x: 700, y: 722, width: 52, height: 52), 14, navy)
    rounded(CGRect(x: 290, y: 250, width: 444, height: 400), 46, rgb(0xFFFFFF), shadow: true)
    let rows: [CGColor] = [navy, blue, sky]
    for (i, color) in rows.enumerated() {
        let y = 540 - CGFloat(i) * 110
        rounded(CGRect(x: 340, y: y, width: 64, height: 64), 18, color)
        rounded(CGRect(x: 432, y: y + 20, width: 240 - CGFloat(i) * 40, height: 24), 12, rgb(0x1B3A8C, 0.16))
    }
default:
    let pocketColor = dark ? blue : navy
    rounded(CGRect(x: 300, y: 545, width: 150, height: 150), 40, dark ? sky : blue, rotate: 12)
    rounded(CGRect(x: 437, y: 585, width: 150, height: 150), 40, dark ? rgb(0xFFFFFF) : sky, rotate: -4)
    rounded(CGRect(x: 574, y: 550, width: 150, height: 150), 40, dark ? rgb(0x8FB2FF, 0.6) : rgb(0x1B3A8C, 0.35), rotate: -14)
    let pocket = CGMutablePath()
    pocket.move(to: CGPoint(x: 240, y: 590))
    pocket.addLine(to: CGPoint(x: 784, y: 590))
    pocket.addLine(to: CGPoint(x: 784, y: 330))
    pocket.addQuadCurve(to: CGPoint(x: 512, y: 230), control: CGPoint(x: 784, y: 230))
    pocket.addQuadCurve(to: CGPoint(x: 240, y: 330), control: CGPoint(x: 240, y: 230))
    pocket.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 20, color: rgb(0x0B1E4A, 0.25))
    ctx.addPath(pocket)
    ctx.setFillColor(pocketColor)
    ctx.fillPath()
    ctx.restoreGState()
    rounded(CGRect(x: 240, y: 560, width: 544, height: 30), 15, rgb(0xFFFFFF, 0.18))
}
ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
