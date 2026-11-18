// Captions over the 3D part (cap_NNNN.png, frames 1-510) and the end card (end_NNNN.png, 108 frames), 1920x1080 at 60 fps.
// Run: swift endcard.swift <outdir>
import AppKit
import CoreText

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let fontDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Resources/Fonts")
for f in (try? FileManager.default.contentsOfDirectory(at: fontDir, includingPropertiesForKeys: nil)) ?? [] {
    CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
}
func geist(_ s: CGFloat, _ w: String) -> NSFont { NSFont(name: "Geist-\(w)", size: s)! }
func pixel(_ s: CGFloat) -> NSFont { NSFont(name: "GeistPixel-Square", size: s)! }
func rgb(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
}
func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                   green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                   blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
}
func clamp(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }
func outCubic(_ t: CGFloat) -> CGFloat { 1 - pow(1 - clamp(t), 3) }
func draw(_ t: String, _ f: NSFont, _ c: NSColor, _ p: CGPoint, kern: CGFloat = 0) {
    NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: c, .kern: kern]).draw(at: p)
}
func size(_ t: String, _ f: NSFont, kern: CGFloat = 0) -> CGSize { (t as NSString).size(withAttributes: [.font: f, .kern: kern]) }

let W = 1920, H = 1080
func frame(_ name: String, clear: Bool, _ body: () -> Void) {
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    if !clear { rgb(0x050507).setFill(); CGRect(x: 0, y: 0, width: W, height: H).fill() }
    body()
    NSGraphicsContext.current = nil
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent(name))
}

// captions: one plain sentence per beat, top left, fade and a short rise
let caps: [(String, Int, Int)] = [
    ("Five agents. Five identical Terminal windows.", 30, 136),
    ("Placard gives each one a name and a color.", 150, 326),
    ("Bright while it works. Dim when it\u{2019}s done.", 338, 404),
    ("When one needs you, you can\u{2019}t miss it.", 418, 510),
]
for f in 1...510 {
    frame(String(format: "cap_%04d.png", f), clear: true) {
        for (text, a, b) in caps where f >= a && f < b {
            let inT = outCubic(CGFloat(f - a) / 18)
            let outT = b == 510 ? 1 : clamp(CGFloat(b - f) / 10)
            let al = inT * outT
            let fnt = geist(50, "SemiBold")
            let p = CGPoint(x: 120, y: 92 + (1 - inT) * 16)
            // a soft dark scrim keeps the line legible over windows
            let s = size(text, fnt)
            let sh = NSShadow(); sh.shadowBlurRadius = 40; sh.shadowColor = NSColor(white: 0, alpha: 0.9 * al); sh.shadowOffset = .zero
            NSGraphicsContext.saveGraphicsState(); sh.set()
            NSColor(white: 0.02, alpha: 0.55 * al).setFill()
            NSBezierPath(roundedRect: CGRect(x: p.x - 26, y: p.y - 14, width: s.width + 52, height: s.height + 28), xRadius: 18, yRadius: 18).fill()
            NSGraphicsContext.restoreGraphicsState()
            draw(text, fnt, NSColor(white: 1, alpha: al), p)
        }
    }
}

func strip(_ r: CGRect, _ fill: NSColor, name: String, task: String, status: String, emoji: String, tick: Int) {
    let p = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
    NSGraphicsContext.saveGraphicsState(); p.addClip()
    let top = mix(fill, .white, 0.12), bot = mix(fill, .black, 0.16)
    for yy in stride(from: r.minY, to: r.maxY, by: 1) {
        mix(top, bot, (yy - r.minY) / r.height).setFill(); CGRect(x: r.minX, y: yy, width: r.width, height: 1).fill()
    }
    let nf = geist(34, "SemiBold")
    draw(name, nf, .white, CGPoint(x: r.minX + 24, y: r.midY - size(name, nf).height / 2))
    let nx = r.minX + 24 + size(name, nf).width
    let chev = NSBezierPath()
    chev.move(to: CGPoint(x: nx + 10, y: r.midY - 3)); chev.line(to: CGPoint(x: nx + 18, y: r.midY + 5)); chev.line(to: CGPoint(x: nx + 26, y: r.midY - 3))
    chev.lineWidth = 3; chev.lineCapStyle = .round; NSColor(white: 1, alpha: 0.7).setStroke(); chev.stroke()
    let tf = geist(24, "Medium")
    draw(task, tf, NSColor(white: 1, alpha: 0.88), CGPoint(x: nx + 42, y: r.midY - size(task, tf).height / 2))
    let ef = NSFont(name: "AppleColorEmoji", size: 32)!
    let ex = r.maxX - 24 - size(emoji, ef).width
    draw(emoji, ef, .white, CGPoint(x: ex, y: r.midY - size(emoji, ef).height / 2))
    let pf = pixel(22)
    let lx = ex - 18 - size(status, pf).width
    draw(status, pf, NSColor(white: 1, alpha: 0.95), CGPoint(x: lx, y: r.midY - size(status, pf).height / 2))
    let order = [0, 1, 3, 2], lit = order[(tick / 6) % 4]
    for c in 0..<4 {
        NSColor(white: 1, alpha: c == lit ? 1 : 0.32).setFill()
        CGRect(x: lx - 28 + CGFloat(c % 2) * 10, y: r.midY - 9 + CGFloat(c / 2) * 10, width: 7, height: 7).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

// end card: wordmark, tagline, then a strip that carries the link
let word = "PLACARD"
for e in 0..<108 {
    frame(String(format: "end_%04d.png", e + 1), clear: false) {
        let fe = CGFloat(e)
        let a1 = outCubic((fe - 14) / 26)
        let f = pixel(210)
        let s = size(word, f, kern: 8)
        draw(word, f, NSColor(white: 1, alpha: a1), CGPoint(x: (CGFloat(W) - s.width) / 2, y: 300 + (1 - a1) * 24), kern: 8)
        let a2 = outCubic((fe - 30) / 24)
        let tf = geist(36, "Medium")
        let t = "Big, loud labels for a screen full of Terminal agents."
        draw(t, tf, NSColor(white: 1, alpha: 0.7 * a2), CGPoint(x: (CGFloat(W) - size(t, tf).width) / 2, y: 568 + (1 - a2) * 16))
        let a3 = outCubic((fe - 44) / 24)
        if a3 > 0 {
            let w: CGFloat = 900, h: CGFloat = 60
            let r = CGRect(x: (CGFloat(W) - w) / 2, y: 690 + (1 - a3) * 22, width: w, height: h)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(a3)
            strip(r, rgb(0x82C91E).blended(withFraction: 0.18, of: .black)!, name: "placard", task: "github.com/karimbabasf/placard",
                  status: "YOUR TURN", emoji: "\u{1FAA7}", tick: e)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
print("captions and end card in \(out.path)")
