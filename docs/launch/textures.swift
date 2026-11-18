// Textures for the launch video wall: per window an unlabeled base, a labeled base, and its strip.
// The hero window also gets a Christmas body sequence. Run: swift textures.swift <outdir>
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
let mono = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
let emojiFont = NSFont(name: "AppleColorEmoji", size: 20)!

func rgb(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
}
func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                   green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                   blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
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

let palette: [UInt32] = [0xD7263D, 0x1C64F2, 0x82C91E, 0xF59F00, 0x9B5DE5, 0x00B8A9, 0xF15BB5, 0xFF6B1A]
let jobs: [(String, String, String)] = [
    ("api", "Refactor the auth middleware", "\u{1F98A}"), ("web", "Pricing page redesign", "\u{1F419}"),
    ("db", "Add the orders index", "\u{1F422}"), ("ios", "Fix the paywall crash", "\u{1F34E}"),
    ("docs", "Write the CLI reference", "\u{1F4DA}"), ("billing", "Stripe webhook retries", "\u{1F4B8}"),
    ("search", "Rank by recency", "\u{1F50E}"), ("ml", "Eval the new reranker", "\u{1F9E0}"),
    ("ops", "Bump the base image", "\u{1F40B}"), ("cli", "Add --json output", "\u{1F6E0}"),
    ("sdk", "Ship the v2 types", "\u{1F4E6}"), ("admin", "Bulk user export", "\u{1F5C2}"),
    ("cron", "Nightly digest job", "\u{23F0}"), ("email", "Welcome sequence copy", "\u{1F48C}"),
    ("infra", "Rotate the staging certs", "\u{1F344}"), ("edge", "Cache the OG images", "\u{26A1}"),
    ("perf", "Kill the N+1 on feed", "\u{1F3CE}"), ("tests", "Fix the flaky e2e", "\u{1F9EA}"),
    ("deps", "Upgrade to React 20", "\u{1F9F9}"), ("ui", "Dark mode tokens", "\u{1F319}"),
    ("data", "Backfill the events table", "\u{1F4CA}"), ("queue", "Dead letter handling", "\u{1F4EE}"),
    ("auth", "Passkeys on login", "\u{1F511}"), ("mobile", "Offline sync", "\u{1F4F1}"),
]
let HERO = 14  // infra: the one that needs you
let pool = [
    "\u{25CF} Read(src/%@/index.ts)", "\u{25CF} Update(src/%@/handler.ts)", "  \u{23BF} +42 -18",
    "\u{25CF} Bash(npm test -- %@)", "  \u{23BF} 128 passed, 0 failed", "\u{25CF} Grep(\"TODO\", src/%@)",
    "  \u{23BF} Found 7 matches", "\u{2733} Thinking about the edge cases...", "\u{25CF} Write(src/%@/types.ts)",
    "  \u{23BF} Wrote 86 lines", "\u{25CF} Task(review the %@ diff)", "\u{25CF} Bash(git diff --stat)",
    "  \u{23BF} 4 files changed", "\u{25CF} Edit(%@.config.json)", "  \u{23BF} Compiled in 2.3s",
]

let PW: CGFloat = 800, PH: CGFloat = 500, TB: CGFloat = 40, RAD: CGFloat = 16
var rng = SystemRandomNumberGenerator()
struct LCG { var s: UInt64; mutating func next() -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int(s >> 33) } }

func render(_ scale: CGFloat, _ w: CGFloat, _ h: CGFloat, _ name: String, _ body: () -> Void) {
    let W = Int(w * scale), H = Int(h * scale)
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    body()
    NSGraphicsContext.current = nil
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}
func rr(_ r: CGRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
func draw(_ t: String, _ f: NSFont, _ c: NSColor, _ p: CGPoint, kern: CGFloat = 0) {
    NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: c, .kern: kern]).draw(at: p)
}
func width(_ t: String, _ f: NSFont) -> CGFloat { (t as NSString).size(withAttributes: [.font: f]).width }

func window(_ i: Int, labeled: Bool, body: NSColor? = nil, ink: NSColor? = nil) {
    let (name, _, _) = jobs[i]
    let color = rgb(palette[i % palette.count])
    let frame = CGRect(x: 0, y: 0, width: PW, height: PH)
    rr(frame, RAD).addClip()
    (body ?? (labeled ? mix(rgb(0x141416), color, 0.16) : rgb(0x18181B))).setFill()
    frame.fill()
    rgb(0x2B2B30).setFill()
    CGRect(x: 0, y: 0, width: PW, height: TB).fill()
    for k in 0..<3 {
        rgb([0xFF5F57, 0xFEBC2E, 0x28C840][k]).setFill()
        NSBezierPath(ovalIn: CGRect(x: 16 + CGFloat(k) * 21, y: 13, width: 13, height: 13)).fill()
    }
    if !labeled {
        let t = "\u{2733} claude \u{2014} ~/dev/\(name) \u{2014} 120\u{00D7}40"
        let f = geist(13, "Medium")
        draw(t, f, rgb(0x8E8E95), CGPoint(x: (PW - width(t, f)) / 2, y: 11))
    }
    var g = LCG(s: UInt64(i * 7919 + 13))
    let textColor = ink ?? NSColor(white: labeled ? 0.93 : 0.62, alpha: 1)
    for li in 0..<17 {
        let line = String(format: pool[g.next() % pool.count], name)
        draw(line, mono, textColor, CGPoint(x: 22, y: TB + 18 + CGFloat(li) * 25))
    }
}

func strip(_ i: Int, status: String) {
    let (name, task, emoji) = jobs[i]
    let fill = rgb(palette[i % palette.count])
    let dark = i % palette.count == 2 || i % palette.count == 3
    let ink: NSColor = dark ? rgb(0x1A1200) : .white
    let s = CGRect(x: 0, y: 0, width: PW - 92, height: 32)
    rr(s, 9).addClip()
    let top = mix(fill, .white, 0.12), bot = mix(fill, .black, 0.14)
    for yy in stride(from: 0, to: s.height, by: 1) {
        mix(top, bot, yy / s.height).setFill()
        CGRect(x: 0, y: yy, width: s.width, height: 1).fill()
    }
    let nf = geist(20, "SemiBold")
    draw(name, nf, ink, CGPoint(x: 14, y: 3))
    let nx = 14 + width(name, nf)
    let chev = NSBezierPath()
    chev.move(to: CGPoint(x: nx + 6, y: 14)); chev.line(to: CGPoint(x: nx + 11, y: 19)); chev.line(to: CGPoint(x: nx + 16, y: 14))
    chev.lineWidth = 2; chev.lineCapStyle = .round
    ink.withAlphaComponent(0.7).setStroke(); chev.stroke()
    draw(task, geist(14, "Medium"), ink.withAlphaComponent(0.85), CGPoint(x: nx + 26, y: 7))
    let ex = s.maxX - 36
    draw(emoji, emojiFont, .white, CGPoint(x: ex, y: 2))
    let pf = pixel(13)
    let lx = ex - 10 - width(status, pf)
    draw(status, pf, ink.withAlphaComponent(0.95), CGPoint(x: lx, y: 9))
    for c in 0..<4 {
        ink.withAlphaComponent(c == 0 || c == 3 ? 1 : 0.35).setFill()
        CGRect(x: lx - 17 + CGFloat(c % 2) * 6, y: 10 + CGFloat(c / 2) * 6, width: 4, height: 4).fill()
    }
}

for i in jobs.indices {
    let sc: CGFloat = i == HERO ? 3 : 2
    render(sc, PW, PH, "w\(i)_a.png") { window(i, labeled: false) }
    render(sc, PW, PH, "w\(i)_b.png") { window(i, labeled: true) }
    render(sc, PW - 92, 32, "s\(i).png") { strip(i, status: "WORKING") }
}
render(3, PW - 92, 32, "s\(HERO)_needs.png") { strip(HERO, status: "NEEDS YOU") }
let cyc = 48
for f in 0..<cyc {
    let (b, t) = christmasAt(CGFloat(f) / CGFloat(cyc))
    render(3, PW, PH, String(format: "xmas_%04d.png", f + 1)) { window(HERO, labeled: true, body: b, ink: t) }
}
print("textures in \(out.path)")
