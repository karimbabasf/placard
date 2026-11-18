// Textures for the launch video: per window an unlabeled base, a labeled base, and its strip in each state.
// The hero window also gets a Christmas body sequence. UI is drawn about 1.5x so strips read at 1080p.
// Run: swift textures.swift <outdir>
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
let mono = NSFont.monospacedSystemFont(ofSize: 19, weight: .regular)
let emojiFont = NSFont(name: "AppleColorEmoji", size: 28)!

func rgb(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
}
func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                   green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                   blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
}
// Placard's own YOUR TURN look: 38% chroma, 62% brightness
func dull(_ c: NSColor) -> NSColor {
    let c = c.usingColorSpace(.sRGB)!
    let l = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    return NSColor(srgbRed: (l + (c.redComponent - l) * 0.38) * 0.62, green: (l + (c.greenComponent - l) * 0.38) * 0.62,
                   blue: (l + (c.blueComponent - l) * 0.38) * 0.62, alpha: 1)
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

// back row api, web, docs; front row infra (hero), db
struct Job { let name, task, emoji: String; let color: UInt32; let darkInk: Bool; let lines: [String] }
let jobs = [
    Job(name: "api", task: "Refactor the auth middleware", emoji: "\u{1F98A}", color: 0xD7263D, darkInk: false,
        lines: ["\u{25CF} Read(src/auth/session.ts)", "  \u{23BF} Read 212 lines", "\u{25CF} Update(src/auth/middleware.ts)",
                "  \u{23BF} +42 -18", "\u{25CF} Bash(npm test -- auth)", "  \u{23BF} 128 passed", "\u{2733} Thinking about token refresh..."]),
    Job(name: "web", task: "Pricing page redesign", emoji: "\u{1F419}", color: 0x1C64F2, darkInk: false,
        lines: ["\u{25CF} Write(app/pricing/page.tsx)", "  \u{23BF} Wrote 186 lines", "\u{25CF} Bash(npm run build)",
                "  \u{23BF} Compiled in 4.1s", "\u{2713} Done. 3 files changed.", "", "\u{276F} "]),
    Job(name: "docs", task: "Write the CLI reference", emoji: "\u{1F4DA}", color: 0x9B5DE5, darkInk: false,
        lines: ["\u{25CF} Read(src/cli/commands.ts)", "\u{25CF} Write(docs/cli.md)", "  \u{23BF} Wrote 340 lines",
                "\u{25CF} Bash(npx markdownlint docs)", "  \u{23BF} 0 problems", "\u{2733} Adding the examples..."]),
    Job(name: "infra", task: "Rotate the staging certs", emoji: "\u{1F344}", color: 0x82C91E, darkInk: true,
        lines: ["\u{25CF} Read(terraform/tls.tf)", "\u{25CF} Bash(terraform plan)", "  \u{23BF} 2 to change",
                "\u{25CF} Bash(terraform apply -target=module.tls)", "", " Do you want to proceed?", " \u{276F} 1. Yes    2. No"]),
    Job(name: "db", task: "Add the orders index", emoji: "\u{1F422}", color: 0xF59F00, darkInk: true,
        lines: ["\u{25CF} Read(db/schema.sql)", "\u{25CF} Write(db/migrations/0042.sql)", "  \u{23BF} CREATE INDEX ...",
                "\u{25CF} Bash(npm run migrate)", "  \u{23BF} Applied in 1.8s", "\u{2713} Done. Query is 40x faster.", "\u{276F} "]),
]
let HERO = 3

let PW: CGFloat = 800, PH: CGFloat = 500, TB: CGFloat = 58, RAD: CGFloat = 18
let SX: CGFloat = 104, SY: CGFloat = 7, SH: CGFloat = 44

func render(_ scale: CGFloat, _ w: CGFloat, _ h: CGFloat, _ name: String, _ body: () -> Void) {
    let W = Int(w * scale), H = Int(h * scale)
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    body()
    NSGraphicsContext.current = nil
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent(name))
}
func rr(_ r: CGRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
func draw(_ t: String, _ f: NSFont, _ c: NSColor, _ p: CGPoint) {
    NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: c]).draw(at: p)
}
func width(_ t: String, _ f: NSFont) -> CGFloat { (t as NSString).size(withAttributes: [.font: f]).width }

func window(_ i: Int, labeled: Bool, body: NSColor? = nil, ink: NSColor? = nil) {
    let j = jobs[i]
    let frame = CGRect(x: 0, y: 0, width: PW, height: PH)
    rr(frame, RAD).addClip()
    (body ?? (labeled ? mix(rgb(0x141416), rgb(j.color), 0.17) : rgb(0x1A1A1D))).setFill()
    frame.fill()
    rgb(0x2C2C31).setFill()
    CGRect(x: 0, y: 0, width: PW, height: TB).fill()
    for k in 0..<3 {
        rgb([0xFF5F57, 0xFEBC2E, 0x28C840][k]).setFill()
        NSBezierPath(ovalIn: CGRect(x: 20 + CGFloat(k) * 26, y: 21, width: 16, height: 16)).fill()
    }
    if !labeled {
        let t = "\u{2733} claude \u{2014} ~/dev \u{2014} 120\u{00D7}40"
        let f = geist(17, "Medium")
        draw(t, f, rgb(0x8E8E95), CGPoint(x: (PW - width(t, f)) / 2 + 30, y: 17))
    }
    let textColor = ink ?? NSColor(white: labeled ? 0.93 : 0.66, alpha: 1)
    for (li, line) in j.lines.enumerated() {
        draw(line, mono, textColor, CGPoint(x: 28, y: TB + 26 + CGFloat(li) * 34))
    }
    if j.lines.last == "\u{276F} " { textColor.setFill(); CGRect(x: 52, y: TB + 30 + CGFloat(j.lines.count - 1) * 34, width: 11, height: 22).fill() }
}

func strip(_ i: Int, _ state: String) {
    let j = jobs[i]
    let turn = state == "YOUR TURN"
    let fill = turn ? dull(rgb(j.color)) : rgb(j.color)
    let ink: NSColor = turn ? NSColor(white: 1, alpha: 0.86) : (j.darkInk ? rgb(0x1A1200) : .white)
    let s = CGRect(x: 0, y: 0, width: PW - SX - 8, height: SH)
    rr(s, 11).addClip()
    let top = mix(fill, .white, 0.12), bot = mix(fill, .black, 0.14)
    for yy in stride(from: 0, to: s.height, by: 1) {
        mix(top, bot, yy / s.height).setFill(); CGRect(x: 0, y: yy, width: s.width, height: 1).fill()
    }
    let nf = geist(28, "SemiBold")
    draw(j.name, nf, ink, CGPoint(x: 18, y: 4))
    let nx = 18 + width(j.name, nf)
    let chev = NSBezierPath()
    chev.move(to: CGPoint(x: nx + 8, y: 19)); chev.line(to: CGPoint(x: nx + 14.5, y: 25.5)); chev.line(to: CGPoint(x: nx + 21, y: 19))
    chev.lineWidth = 2.6; chev.lineCapStyle = .round
    ink.withAlphaComponent(0.7).setStroke(); chev.stroke()
    draw(j.task, geist(19, "Medium"), ink.withAlphaComponent(0.86), CGPoint(x: nx + 34, y: 10))
    let ex = s.maxX - 46
    draw(j.emoji, emojiFont, .white, CGPoint(x: ex, y: 3))
    let pf = pixel(18)
    let lx = ex - 14 - width(state, pf)
    draw(state, pf, ink.withAlphaComponent(0.95), CGPoint(x: lx, y: 12))
    for c in 0..<4 {
        ink.withAlphaComponent(turn || c == 0 || c == 3 ? 1 : 0.35).setFill()
        CGRect(x: lx - 22 + CGFloat(c % 2) * 8, y: 14 + CGFloat(c / 2) * 8, width: 5, height: 5).fill()
    }
}

for i in jobs.indices {
    render(2.5, PW, PH, "w\(i)_a.png") { window(i, labeled: false) }
    render(2.5, PW, PH, "w\(i)_b.png") { window(i, labeled: true) }
    render(2.5, PW - SX - 8, SH, "s\(i)_work.png") { strip(i, "WORKING") }
    render(2.5, PW - SX - 8, SH, "s\(i)_turn.png") { strip(i, "YOUR TURN") }
}
render(2.5, PW - SX - 8, SH, "s\(HERO)_needs.png") { strip(HERO, "NEEDS YOU") }
let cyc = 48
for f in 0..<cyc {
    let (b, t) = christmasAt(CGFloat(f) / CGFloat(cyc))
    render(2.5, PW, PH, String(format: "xmas_%04d.png", f + 1)) { window(HERO, labeled: true, body: b, ink: t) }
}
// soft drop shadow, 20% larger than a window
render(1, PW * 1.3, PH * 1.3, "shadow.png") {
    let sh = NSShadow(); sh.shadowBlurRadius = 60; sh.shadowOffset = .zero; sh.shadowColor = NSColor(white: 0, alpha: 0.9)
    sh.set()
    NSColor(white: 0, alpha: 0.9).setFill()
    rr(CGRect(x: PW * 0.15, y: PH * 0.15, width: PW, height: PH), RAD).fill()
}
print("textures in \(out.path)")
