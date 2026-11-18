// End card (frames 206-300) and the caption overlay for the 3D part (frames 1-205), 1920x1080 at 60 fps.
// Run: swift endcard.swift <outdir>   writes end_NNNN.png and cap_NNNN.png
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
func rgb(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                   green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                   blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
}
func clamp(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }
func outExpo(_ t: CGFloat) -> CGFloat { t >= 1 ? 1 : 1 - pow(2, -10 * t) }
func inOutCubic(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func draw(_ t: String, _ f: NSFont, _ c: NSColor, _ p: CGPoint, kern: CGFloat = 0) {
    NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: c, .kern: kern]).draw(at: p)
}
func size(_ t: String, _ f: NSFont, kern: CGFloat = 0) -> CGSize { (t as NSString).size(withAttributes: [.font: f, .kern: kern]) }

let W = 1920, H = 1080
let palette: [UInt32] = [0xD7263D, 0x1C64F2, 0x82C91E, 0xF59F00, 0x9B5DE5, 0x00B8A9, 0xF15BB5, 0xFF6B1A]
let flood = rgb(0xF06BBE)  // the hero strip as the whip lands in it
let bayer: [CGFloat] = [0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38,
    60, 28, 52, 20, 62, 30, 54, 22, 3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25, 15, 47, 7, 39, 13, 45, 5, 37,
    63, 31, 55, 23, 61, 29, 53, 21].map { (CGFloat($0) + 0.5) / 64 }

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

func strip(_ r: CGRect, _ fill: NSColor, name: String, task: String, status: String, emoji: String, tick: Int, scale k: CGFloat) {
    let p = NSBezierPath(roundedRect: r, xRadius: 13 * k, yRadius: 13 * k)
    NSGraphicsContext.saveGraphicsState(); p.addClip()
    let top = mix(fill, .white, 0.12), bot = mix(fill, .black, 0.16)
    for yy in stride(from: r.minY, to: r.maxY, by: 1) {
        mix(top, bot, (yy - r.minY) / r.height).setFill()
        CGRect(x: r.minX, y: yy, width: r.width, height: 1).fill()
    }
    let nf = geist(30 * k, "SemiBold")
    let ny = r.midY - size(name, nf).height / 2
    draw(name, nf, .white, CGPoint(x: r.minX + 22 * k, y: ny))
    let nx = r.minX + 22 * k + size(name, nf).width
    let chev = NSBezierPath()
    chev.move(to: CGPoint(x: nx + 9 * k, y: r.midY - 3 * k)); chev.line(to: CGPoint(x: nx + 16 * k, y: r.midY + 4 * k))
    chev.line(to: CGPoint(x: nx + 23 * k, y: r.midY - 3 * k))
    chev.lineWidth = 3 * k; chev.lineCapStyle = .round; NSColor(white: 1, alpha: 0.7).setStroke(); chev.stroke()
    let tf = geist(21 * k, "Medium")
    draw(task, tf, NSColor(white: 1, alpha: 0.86), CGPoint(x: nx + 38 * k, y: r.midY - size(task, tf).height / 2))
    let ef = NSFont(name: "AppleColorEmoji", size: 28 * k)!
    let ex = r.maxX - 22 * k - size(emoji, ef).width
    draw(emoji, ef, .white, CGPoint(x: ex, y: r.midY - size(emoji, ef).height / 2))
    let pf = pixel(20 * k)
    let lx = ex - 16 * k - size(status, pf).width
    draw(status, pf, NSColor(white: 1, alpha: 0.95), CGPoint(x: lx, y: r.midY - size(status, pf).height / 2))
    let order = [0, 1, 3, 2], lit = order[(tick / 5) % 4]
    for c in 0..<4 {
        NSColor(white: 1, alpha: c == lit ? 1 : 0.32).setFill()
        CGRect(x: lx - 26 * k + CGFloat(c % 2) * 9 * k, y: r.midY - 8 * k + CGFloat(c / 2) * 9 * k, width: 6 * k, height: 6 * k).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

let word = "PLACARD"
let bands = 7
let total = 95
for e in 0..<total {
    frame(String(format: "end_%04d.png", e + 1), clear: false) {
        let fe = CGFloat(e)
        // 1. bands of strips, each a palette color with the wordmark repeated, sliding in from alternate sides
        let collapse = inOutCubic(clamp((fe - 30) / 14))
        let bh = CGFloat(H) / CGFloat(bands)
        for b in 0..<bands {
            let enter = outExpo(clamp((fe - 2 - CGFloat(b) * 1.6) / 16))
            let dir: CGFloat = b % 2 == 0 ? 1 : -1
            let drift = (1 - enter) * CGFloat(W) * 1.1 * dir + fe * 9 * dir
            let cy = CGFloat(b) * bh + bh / 2
            let y = cy + (CGFloat(H) / 2 - cy) * collapse
            let h = bh * (1 - collapse) - 6
            guard h > 1 else { continue }
            let r = CGRect(x: 0, y: y - h / 2, width: CGFloat(W), height: h)
            NSGraphicsContext.saveGraphicsState(); r.clip()
            let col = rgb(palette[(b * 3 + 1) % palette.count])
            col.setFill(); CGRect(x: drift - CGFloat(W) * 1.2, y: r.minY, width: CGFloat(W) * 3.4, height: h).fill()
            let f = pixel(bh * 0.86)
            let s = size(word + "  ", f, kern: 4)
            var x = drift - CGFloat(W) * 1.2 + CGFloat(b * 137 % 300)
            let ink: NSColor = [2, 3].contains((b * 3 + 1) % palette.count) ? rgb(0x101008) : .white
            while x < CGFloat(W) * 2.3 {
                draw(word, f, ink, CGPoint(x: x, y: cy - s.height / 2 + (y - cy)), kern: 4); x += s.width
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        // 2. the flood from the whip dissolves through an 8 px ordered dither, left to right
        let cell = 8
        for cy in stride(from: 0, to: H, by: cell) {
            for cx in stride(from: 0, to: W, by: cell) {
                let th = bayer[((cy / cell) & 7) * 8 + ((cx / cell) & 7)]
                let prog = fe / 13 * 1.5 - CGFloat(cx) / CGFloat(W) * 0.5
                if th > prog { flood.setFill(); CGRect(x: cx, y: cy, width: cell, height: cell).fill() }
            }
        }
        // 3. wordmark slams in as the bands collapse
        let land = clamp((fe - 40) / 7)
        if fe >= 38 {
            let k = 1 + (1 - outExpo(land)) * 0.35
            let f = pixel(250 * k)
            let s = size(word, f, kern: 10 * k)
            let a = clamp((fe - 38) / 3)
            draw(word, f, NSColor(white: 1, alpha: a), CGPoint(x: (CGFloat(W) - s.width) / 2, y: 300 - (s.height - size(word, pixel(250), kern: 10).height) / 2), kern: 10 * k)
            if fe >= 44 && fe < 52 { NSColor(white: 1, alpha: 0.18 * (1 - (fe - 44) / 8)).setFill(); CGRect(x: 0, y: 0, width: W, height: H).fill() }
        }
        // 4. tagline, a real strip landing, the link
        if fe >= 50 {
            let a = clamp((fe - 50) / 10)
            let tf = geist(34, "Medium")
            let t = "Big, loud labels for a screen full of Terminal agents."
            let ts = size(t, tf)
            draw(t, tf, NSColor(white: 1, alpha: 0.72 * a), CGPoint(x: (CGFloat(W) - ts.width) / 2, y: 585 + (1 - outExpo(a)) * 24))
        }
        if fe >= 56 {
            let p = outExpo(clamp((fe - 56) / 12))
            let k: CGFloat = 1.25 + (1 - p) * 0.4
            let w: CGFloat = 820 * k / 1.25, h: CGFloat = 46 * k / 1.25
            let r = CGRect(x: (CGFloat(W) - w) / 2, y: 690 - (1 - p) * 60, width: w, height: h)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(clamp((fe - 56) / 4))
            strip(r, rgb(0xF15BB5), name: "placard", task: "v0.1.0 is out", status: "YOUR TURN", emoji: "\u{1FAA7}", tick: e, scale: k / 1.25 * 1.0)
            NSGraphicsContext.restoreGraphicsState()
        }
        if fe >= 64 {
            let a = clamp((fe - 64) / 10)
            let uf = geist(24, "Medium")
            let u = "github.com/karimbabasf/placard"
            draw(u, uf, NSColor(white: 1, alpha: 0.5 * a), CGPoint(x: (CGFloat(W) - size(u, uf).width) / 2, y: 910))
        }
    }
}

// captions over the 3D part, typed on with a block cursor
let caps: [(String, Int, Int)] = [("24 agents running", 16, 96), ("which one needs you?", 150, 196)]
for f in 1...205 {
    frame(String(format: "cap_%04d.png", f), clear: true) {
        for (text, a, b) in caps where f >= a && f < b {
            let n = min(text.count, (f - a) / 2)
            let shown = String(text.prefix(n))
            let fnt = pixel(46)
            let fade = clamp(CGFloat(b - f) / 8)
            let p = CGPoint(x: 96, y: 930)
            NSColor(white: 0, alpha: 0.55 * fade).setFill()
            let s = size(text, fnt)
            CGRect(x: p.x - 18, y: p.y - 10, width: s.width + 64, height: s.height + 20).fill()
            draw(shown, fnt, NSColor(white: 1, alpha: fade), p)
            if (f / 8) % 2 == 0 || n < text.count {
                NSColor(white: 1, alpha: fade).setFill()
                CGRect(x: p.x + size(shown, fnt).width + 6, y: p.y + 6, width: 22, height: s.height - 10).fill()
            }
        }
    }
}
print("end card and captions in \(out.path)")
