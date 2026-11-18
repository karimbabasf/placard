// Renders docs/hero.gif: three mock Terminal windows wearing Placard strips,
// every fill pushed through a 4x4 ordered dither, text kept crisp on top.
// Run: swift docs/hero.swift && see docs/make-hero.sh
import AppKit
import CoreText

let W = 1200, H = 660
let frames = 60
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/placard-hero")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let fontDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Fonts")
for f in (try? FileManager.default.contentsOfDirectory(at: fontDir, includingPropertiesForKeys: nil)) ?? [] {
    CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
}
func geist(_ s: CGFloat, _ w: String) -> NSFont { NSFont(name: "Geist-\(w)", size: s)! }
func pixel(_ s: CGFloat) -> NSFont { NSFont(name: "GeistPixel-Square", size: s)! }
let mono = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
let emojiFont = NSFont(name: "AppleColorEmoji", size: 18)!

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                   green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                   blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
}
func dull(_ c: NSColor) -> NSColor {
    let c = c.usingColorSpace(.sRGB)!
    let l = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    let k: CGFloat = 0.38
    return NSColor(srgbRed: (l + (c.redComponent - l) * k) * 0.62, green: (l + (c.greenComponent - l) * k) * 0.62,
                   blue: (l + (c.blueComponent - l) * k) * 0.62, alpha: 1)
}

enum State { case working, yourTurn, needsYou }
struct Win {
    let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    let name: String, task: String, emoji: String, color: NSColor, darkInk: Bool
    let lines: [String]
}

let christmas: [(NSColor, NSColor)] = [
    (rgb(0x9E0A1A), rgb(0x8CFF9E)), (rgb(0x086B2B), rgb(0xFFDB40)), (rgb(0x8C6100), rgb(0xFFFFFF)),
    (rgb(0x0A421F), rgb(0xFF525C)), (rgb(0xB3142A), rgb(0xFFFFFF)), (rgb(0x0D8038), rgb(0xFF666B)),
]
func christmasAt(_ t: CGFloat) -> (NSColor, NSColor) {
    let p = t * CGFloat(christmas.count)
    let i = Int(p) % christmas.count, j = (i + 1) % christmas.count, f = p - floor(p)
    return (mix(christmas[i].0, christmas[j].0, f), mix(christmas[i].1, christmas[j].1, f))
}

let wins = [
    Win(x: 48, y: 196, w: 690, h: 196, name: "api", task: "Refactor the auth middleware", emoji: "\u{1F98A}",
        color: rgb(0xD7263D), darkInk: false,
        lines: ["\u{25CF} Reading src/auth/session.ts", "\u{25CF} Update(src/auth/middleware.ts)", "  \u{23BF} +42 -18", "\u{2733} Thinking about token refresh..."]),
    Win(x: 470, y: 300, w: 690, h: 196, name: "web", task: "Pricing page redesign", emoji: "\u{1F419}",
        color: rgb(0x1C64F2), darkInk: false,
        lines: ["\u{25CF} Write(app/pricing/page.tsx)", "\u{25CF} Bash(npm run build)", "  \u{23BF} Compiled in 4.1s", "\u{2713} Done. 3 files changed."]),
    Win(x: 150, y: 420, w: 690, h: 196, name: "infra", task: "Rotate the staging certs", emoji: "\u{1F344}",
        color: rgb(0x82C91E), darkInk: true,
        lines: ["\u{25CF} Bash(terraform apply -target=module.tls)", "", " Do you want to proceed?", " \u{276F} 1. Yes    2. No"]),
]

func state(_ i: Int, _ f: Int) -> State {
    switch i {
    case 0: return .working
    case 1: return f < 30 ? .working : .yourTurn
    default: return f < 18 ? .yourTurn : .needsYou
    }
}

let bayer: [CGFloat] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { (CGFloat($0) + 0.5) / 16 }

func rounded(_ r: CGRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }

func draw(_ text: String, _ font: NSFont, _ color: NSColor, _ p: CGPoint, kern: CGFloat = 0) {
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern]).draw(at: p)
}
func width(_ text: String, _ font: NSFont, kern: CGFloat = 0) -> CGFloat {
    (text as NSString).size(withAttributes: [.font: font, .kern: kern]).width
}

for f in 0..<frames {
    let t = CGFloat(f) / CGFloat(frames)
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(H))
    ctx.scaleBy(x: 1, y: -1)
    let g = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current = g

    // ---- pass 1: fills (these get dithered)
    let bgTop = rgb(0x101014), bgBot = rgb(0x1C1A24)
    for y in stride(from: 0, to: H, by: 4) {
        mix(bgTop, bgBot, CGFloat(y) / CGFloat(H)).setFill()
        NSRect(x: 0, y: CGFloat(y), width: CGFloat(W), height: 4).fill()
    }
    var stripRects: [(CGRect, Int)] = []
    for (i, w) in wins.enumerated() {
        let st = state(i, f)
        let frame = CGRect(x: w.x, y: w.y, width: w.w, height: w.h)
        var body = mix(rgb(0x141416), w.color, 0.14)
        if st == .needsYou { body = christmasAt(t * 2).0 }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowBlurRadius = 28
        shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
        shadow.set()
        body.setFill()
        rounded(frame, 16).fill()
        NSGraphicsContext.restoreGraphicsState()
        // title bar
        NSGraphicsContext.saveGraphicsState()
        rounded(frame, 16).addClip()
        rgb(0x2B2B30).setFill()
        CGRect(x: w.x, y: w.y, width: w.w, height: 32).fill()
        NSGraphicsContext.restoreGraphicsState()
        // strip
        let strip = CGRect(x: w.x + 76, y: w.y + 3, width: w.w - 79, height: 26)
        let fill = st == .yourTurn ? dull(w.color) : w.color
        let top = mix(fill, .white, 0.10), bot = mix(fill, .black, 0.14)
        NSGraphicsContext.saveGraphicsState()
        rounded(strip, 7).addClip()
        for yy in stride(from: strip.minY, to: strip.maxY, by: 2) {
            mix(top, bot, (yy - strip.minY) / strip.height).setFill()
            CGRect(x: strip.minX, y: yy, width: strip.width, height: 2).fill()
        }
        if st == .working {
            let sweep = (t * 1.6 + CGFloat(i) * 0.37).truncatingRemainder(dividingBy: 1.6)
            if sweep < 1 {
                let cx = strip.minX - 110 + (strip.width + 220) * sweep
                let grad = NSGradient(colors: [NSColor(white: 1, alpha: 0), NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0)])!
                grad.draw(in: CGRect(x: cx - 110, y: strip.minY, width: 220, height: strip.height), angle: 0)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        stripRects.append((strip, i))
    }

    // ordered dither on the strips only: 2 px cells, 5 levels per channel.
    // Dark fills stay smooth: a dot grid on near-black moires when the README scales the GIF, and shimmers on scroll.
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let levels: CGFloat = 5
    func inStrip(_ x: Int, _ y: Int, _ r: CGRect) -> Bool {
        let px = CGFloat(x) + 0.5, py = CGFloat(y) + 0.5, rad: CGFloat = 7
        guard r.contains(CGPoint(x: px, y: py)) else { return false }
        let dx = max(r.minX + rad - px, px - (r.maxX - rad), 0), dy = max(r.minY + rad - py, py - (r.maxY - rad), 0)
        return dx * dx + dy * dy <= rad * rad
    }
    for (i, (r, _)) in stripRects.enumerated() {
        // a window drawn later covers part of this strip: leave those pixels alone
        let covers = wins[(i + 1)...].map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
        for y in Int(r.minY)..<Int(r.maxY.rounded(.up)) { for x in Int(r.minX)..<Int(r.maxX.rounded(.up)) {
            guard inStrip(x, y, r), !covers.contains(where: { $0.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) }) else { continue }
            let th = bayer[((y / 2) & 3) * 4 + ((x / 2) & 3)]
            let o = (y * W + x) * 4
            for c in 0..<3 {
                let v = CGFloat(data[o + c]) / 255 * (levels - 1)
                let q = min(levels - 1, floor(v + th))
                data[o + c] = UInt8(q / (levels - 1) * 255)
            }
        } }
    }

    // ---- pass 2: crisp text and controls
    draw("PLACARD", pixel(66), .white, CGPoint(x: 48, y: 40), kern: 2)
    draw("Big, loud labels for a screen full of Terminal agents.", geist(23, "Medium"), NSColor(white: 1, alpha: 0.72), CGPoint(x: 52, y: 124))

    for (i, w) in wins.enumerated() {
        let st = state(i, f)
        let strip = stripRects[i].0
        // windows drawn later sit in front: keep this window's text out from under them
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(rect: CGRect(x: 0, y: 0, width: W, height: H))
        for later in wins[(i + 1)...] { clip.append(rounded(CGRect(x: later.x, y: later.y, width: later.w, height: later.h), 16)) }
        clip.windingRule = .evenOdd
        clip.addClip()
        // traffic lights
        for k in 0..<3 {
            rgb([0xFF5F57, 0xFEBC2E, 0x28C840][k]).setFill()
            NSBezierPath(ovalIn: CGRect(x: w.x + 14 + CGFloat(k) * 20, y: w.y + 10, width: 12, height: 12)).fill()
        }
        let ink: NSColor = (st == .yourTurn) ? NSColor(white: 1, alpha: 0.86) : (w.darkInk ? rgb(0x1A1200) : .white)
        draw(w.name, geist(17, "SemiBold"), ink, CGPoint(x: strip.minX + 14, y: strip.minY + 2))
        let nx = strip.minX + 14 + width(w.name, geist(17, "SemiBold"))
        let chev = NSBezierPath()
        chev.move(to: CGPoint(x: nx + 5, y: strip.midY - 2))
        chev.line(to: CGPoint(x: nx + 9.5, y: strip.midY + 2.5))
        chev.line(to: CGPoint(x: nx + 14, y: strip.midY - 2))
        chev.lineWidth = 1.8
        chev.lineCapStyle = .round
        ink.withAlphaComponent(0.7).setStroke()
        chev.stroke()
        draw(w.task, geist(12.5, "Medium"), ink.withAlphaComponent(0.84), CGPoint(x: nx + 24, y: strip.minY + 5))
        // emoji, status, spinner
        let ex = strip.maxX - 12 - 20
        draw(w.emoji, emojiFont, .white, CGPoint(x: ex - 2, y: strip.minY + 1))
        let label = st == .working ? "WORKING" : (st == .yourTurn ? "YOUR TURN" : "NEEDS YOU")
        let lw = width(label, pixel(12))
        let lx = ex - 8 - lw
        draw(label, pixel(12), ink.withAlphaComponent(0.92), CGPoint(x: lx, y: strip.minY + 6))
        let lit = (f / 3) % 4
        let order = [0, 1, 3, 2]
        for c in 0..<4 {
            let on = st == .yourTurn || order[lit] == c
            ink.withAlphaComponent(on ? 1 : 0.3).setFill()
            CGRect(x: lx - 15 + CGFloat(c % 2) * 5, y: strip.midY - 4 + CGFloat(c / 2) * 5, width: 3, height: 3).fill()
        }
        // terminal content
        var textColor = NSColor(white: 0.93, alpha: 1)
        if st == .needsYou { textColor = christmasAt(t * 2).1 }
        for (li, line) in w.lines.enumerated() {
            draw(line, mono, textColor, CGPoint(x: w.x + 22, y: w.y + 50 + CGFloat(li) * 24))
        }
        if i == 0 {
            let cursorOn = (f / 6) % 2 == 0
            if cursorOn { textColor.setFill(); CGRect(x: w.x + 22, y: w.y + 50 + 4 * 24 + 2, width: 9, height: 17).fill() }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.current = nil
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(String(format: "f%03d.png", f)))
}
print("wrote \(frames) frames to \(out.path)")
