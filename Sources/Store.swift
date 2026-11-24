import AppKit

struct Swatch {
    let name: String
    let hex: UInt32
    let darkText: Bool
}

enum Palette {
    // Deep enough that white text clears 4.5:1; amber carries dark text instead.
    // Spread for maximum OKLab distance, lightness mixed on purpose: four deep
    // colors carry white text, four bright ones carry dark ink (all 4.5:1 or more).
    static let all: [Swatch] = [
        Swatch(name: "Red", hex: 0xD7263D, darkText: false),
        Swatch(name: "Orange", hex: 0xE8590C, darkText: true),
        Swatch(name: "Yellow", hex: 0xFFD43B, darkText: true),
        Swatch(name: "Lime", hex: 0x82C91E, darkText: true),
        Swatch(name: "Cyan", hex: 0x15AABF, darkText: true),
        Swatch(name: "Blue", hex: 0x1C64F2, darkText: false),
        Swatch(name: "Violet", hex: 0x7C4DFF, darkText: false),
        Swatch(name: "Pink", hex: 0xF783AC, darkText: true),
    ]

    /// OKLab, for distances that match what the eye sees.
    static func oklab(_ i: Int) -> (Double, Double, Double) { oklab(rgb(i)) }

    static func oklab(_ c: (Double, Double, Double)) -> (Double, Double, Double) {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(c.0), g = lin(c.1), b = lin(c.2)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func srgb(oklab c: (Double, Double, Double)) -> (Double, Double, Double) {
        func gam(_ v: Double) -> Double { let v = max(0, min(1, v)); return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }
        let l = pow(c.0 + 0.3963377774 * c.1 + 0.2158037573 * c.2, 3)
        let m = pow(c.0 - 0.1055613458 * c.1 - 0.0638541728 * c.2, 3)
        let s = pow(c.0 - 0.0894841775 * c.1 - 1.2914855480 * c.2, 3)
        return (gam(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                gam(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }

    /// The group hue at OKLab lightness `l`, chroma scaled by `k`.
    static func shade(_ i: Int, l: Double, chroma k: Double) -> (Double, Double, Double) {
        let c = oklab(i)
        return srgb(oklab: (l, c.1 * k, c.2 * k))
    }

    static func distance(_ a: Int, _ b: Int) -> Double {
        let x = oklab(a), y = oklab(b)
        return sqrt(pow(x.0 - y.0, 2) + pow(x.1 - y.1, 2) + pow(x.2 - y.2, 2))
    }

    /// The palette color farthest from every color in `used` (max of the min distance).
    static func mostDistinct(from used: [Int]) -> Int {
        guard !used.isEmpty else { return 5 }      // blue first
        let free = (0..<all.count).filter { !used.contains($0) }
        let pool = free.isEmpty ? Array(0..<all.count) : free
        return pool.max { a, b in
            used.map { distance(a, $0) }.min()! < used.map { distance(b, $0) }.min()!
        }!
    }

    /// Two colors closer than this read as "the same" from across the room.
    static let clash = 0.13

    static func rgb(_ i: Int) -> (Double, Double, Double) {
        let h = all[((i % all.count) + all.count) % all.count].hex
        return (Double((h >> 16) & 0xFF) / 255, Double((h >> 8) & 0xFF) / 255, Double(h & 0xFF) / 255)
    }

    static func fill(_ i: Int) -> NSColor {
        let (r, g, b) = rgb(i)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// Desaturated and darker: the "not working" look. Hue stays readable.
    static func dulled(_ i: Int) -> (Double, Double, Double) {
        let (r, g, b) = rgb(i)
        let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let k = 0.38                                   // keep 38% of the chroma
        return ((l + (r - l) * k) * 0.62, (l + (g - l) * k) * 0.62, (l + (b - l) * k) * 0.62)
    }

    /// Dark mode fill: a deep shade of the hue. Same lightness for every color,
    /// so yellow no longer outshouts blue; the idle shade is darker and grayer.
    static func darkFill(_ i: Int, dull: Bool) -> (Double, Double, Double) {
        shade(i, l: dull ? 0.27 : 0.34, chroma: dull ? 0.3 : 0.62)
    }

    /// Dark mode ink: a pale tint of the same hue (about 10:1 on the live fill).
    static func darkInk(_ i: Int, dull: Bool) -> NSColor {
        let (r, g, b) = shade(i, l: dull ? 0.78 : 0.93, chroma: dull ? 0.14 : 0.32)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    static func ink(_ i: Int, dull: Bool, dark: Bool) -> NSColor {
        dark ? darkInk(i, dull: dull) : ink(i, dull: dull)
    }

    static func ink(_ i: Int, dull: Bool) -> NSColor {
        guard dull else { return ink(i) }
        return NSColor(white: 1, alpha: 0.86)
    }

    static func ink(_ i: Int) -> NSColor {
        all[((i % all.count) + all.count) % all.count].darkText
            ? NSColor(srgbRed: 0.10, green: 0.07, blue: 0.0, alpha: 1)
            : .white
    }

    /// Terminal background tint: the group hue mixed into the window's own background.
    static func mixed(_ c: (Double, Double, Double), over base: [Int], mix: Double) -> [Int] {
        zip([c.0, c.1, c.2], base.count == 3 ? base : [0, 0, 0]).map { v, o in
            Int(((Double(o) / 65535) * (1 - mix) + v * mix) * 65535)
        }
    }

    static func tint(_ i: Int, over base: [Int], mix forced: Double? = nil) -> [Int] {
        let (r, g, b) = rgb(i)
        let light = base.count == 3 && base.reduce(0, +) > 3 * 32768
        let mix = forced ?? (light ? 0.12 : 0.16)
        return zip([r, g, b], base.count == 3 ? base : [0, 0, 0]).map { c, o in
            let ov = Double(o) / 65535
            return Int(((ov * (1 - mix)) + c * mix) * 65535)
        }
    }
}

struct Group: Codable, Equatable {
    var id: UUID
    var name: String
    var color: Int
    var pinned: Bool? = nil      // color chosen by hand
    var auto: Bool? = nil        // named by auto-label, not by hand
}

struct Saved: Codable {
    var groups: [Group] = []
    var windows: [String: UUID] = [:]      // Terminal window id -> group id
    var originalBackground: [String: [Int]] = [:]
    var tint: Bool = true
    var didFirstLaunch: Bool = false
    var hidden: Bool? = nil                 // labels turned off, handles stay
    var emoji: [String: String]? = nil      // Terminal window id -> emoji
    var tasks: [String: String]? = nil      // Terminal window id -> task text you typed over the title
    var auto: Bool? = nil                   // auto-label agent windows (default on)
    var flashing: [Int]? = nil              // windows mid Christmas mode, so a killed Placard can put them back
    var flash: Bool? = nil                  // Christmas mode when an agent needs you (default on)
    var autoSkip: [String]? = nil           // windows whose label you removed: never auto-label again
    var appearance: String? = nil           // "loud" or "dark"; nil follows the system
}

/// Strip look: the loud saturated fills, or deep shades for a dark desktop.
enum Appearance: String, CaseIterable {
    case system, loud, dark
    var title: String { self == .system ? "Match System" : self == .loud ? "Loud" : "Dark" }
}

@MainActor
enum Look {
    /// Cached: read every frame by every strip.
    private(set) static var dark = false
    static func update() {
        switch Store.shared.appearance {
        case .loud: dark = false
        case .dark: dark = true
        case .system: dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
}

enum Emoji {
    // Distinct silhouettes and colors so two never read alike at a glance.
    static let pool = ["\u{1F98A}", "\u{1F419}", "\u{1F989}", "\u{1F41D}", "\u{1F996}", "\u{1F422}", "\u{1F984}", "\u{1F433}",
                       "\u{1F980}", "\u{1F438}", "\u{1F981}", "\u{1F43C}", "\u{1F427}", "\u{1F9A9}", "\u{1F344}", "\u{1F335}",
                       "\u{1F525}", "\u{26A1}", "\u{1F319}", "\u{1FA90}", "\u{1F34B}", "\u{1F349}", "\u{1F3AF}", "\u{1F680}",
                       "\u{1F6F8}", "\u{1F9CA}", "\u{1F3B2}", "\u{1F9F2}", "\u{1F98B}", "\u{1F35C}", "\u{1F95D}", "\u{1F47E}"]
}

@MainActor
final class Store {
    static let shared = Store()
    private(set) var saved = Saved()
    var onChange: (() -> Void)?

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Placard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = s
            rebalance()
            for k in saved.windows.keys { if let id = Int(k) { assignEmoji(id) } }
            if let data = try? JSONEncoder().encode(saved) { try? data.write(to: url, options: .atomic) }
        }
    }

    private func commit() {
        rebalance()
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: url, options: .atomic) }
        onChange?()
    }

    var groups: [Group] { saved.groups }
    var tint: Bool {
        get { saved.tint }
        set { saved.tint = newValue; commit() }
    }

    var hidden: Bool {
        get { saved.hidden ?? false }
        set { saved.hidden = newValue; commit() }
    }

    var auto: Bool {
        get { saved.auto ?? true }
        set { saved.auto = newValue; commit() }
    }

    var flash: Bool {
        get { saved.flash ?? true }
        set { saved.flash = newValue; commit() }
    }

    var appearance: Appearance {
        get { saved.appearance.flatMap(Appearance.init(rawValue:)) ?? .system }
        set { saved.appearance = newValue == .system ? nil : newValue.rawValue; Look.update(); commit() }
    }

    var flashing: [Int] { saved.flashing ?? [] }
    func setFlashing(_ id: Int, _ on: Bool) {
        var s = Set(saved.flashing ?? [])
        if on { s.insert(id) } else { s.remove(id) }
        saved.flashing = s.isEmpty ? nil : s.sorted()
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: url, options: .atomic) }
    }

    func isSkipped(_ id: Int) -> Bool { saved.autoSkip?.contains(String(id)) ?? false }

    func emoji(forWindow id: Int) -> String? { saved.emoji?[String(id)] }

    func task(forWindow id: Int) -> String? { saved.tasks?[String(id)] }
    /// Empty text goes back to the task Terminal's title shows.
    func setTask(_ text: String, forWindow id: Int) {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        var map = saved.tasks ?? [:]
        map[String(id)] = clean.isEmpty ? nil : clean
        saved.tasks = map
        commit()
    }

    /// A random emoji no other labeled window is using right now.
    private func assignEmoji(_ id: Int, reroll: Bool = false) {
        var map = saved.emoji ?? [:]
        if !reroll, map[String(id)] != nil { return }
        let taken = Set(map.filter { $0.key != String(id) }.values)
        let free = Emoji.pool.filter { !taken.contains($0) && $0 != map[String(id)] }
        map[String(id)] = (free.isEmpty ? Emoji.pool : free).randomElement()!
        saved.emoji = map
    }

    func shuffleEmoji(_ id: Int) { assignEmoji(id, reroll: true); commit() }

    func markFirstLaunchDone() { saved.didFirstLaunch = true; commit() }

    func group(forWindow id: Int) -> Group? {
        guard let gid = saved.windows[String(id)] else { return nil }
        return saved.groups.first { $0.id == gid }
    }

    func group(named name: String) -> Group? {
        saved.groups.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func windows(in group: Group) -> [Int] {
        saved.windows.filter { $0.value == group.id }.compactMap { Int($0.key) }.sorted()
    }

    var labeledWindows: [Int] { saved.windows.keys.compactMap { Int($0) } }

    func nextFreeColor() -> Int { Palette.mostDistinct(from: saved.groups.map { $0.color }) }

    /// Recolors any auto-colored group that sits too close to another open group.
    /// Colors you picked yourself are pinned and never move.
    private func rebalance() {
        for i in saved.groups.indices where saved.groups[i].pinned != true {
            let others = saved.groups.indices
                .filter { $0 != i && ($0 < i || saved.groups[$0].pinned == true) }
                .map { saved.groups[$0].color }
            let c = saved.groups[i].color
            let nearest = others.map { Palette.distance($0, c) }.min() ?? 1
            guard nearest < Palette.clash else { continue }
            let pick = Palette.mostDistinct(from: others)
            if (others.map { Palette.distance($0, pick) }.min() ?? 1) > nearest { saved.groups[i].color = pick }
        }
    }

    /// Joins an existing group by name, or creates one. Returns the group.
    @discardableResult
    func label(window id: Int, name: String, color: Int?, pinned: Bool = false, auto: Bool = false) -> Group {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var g: Group
        if let existing = group(named: clean) {
            g = existing
            if let c = color, c != existing.color, let i = saved.groups.firstIndex(of: existing) {
                saved.groups[i].color = c
                if pinned { saved.groups[i].pinned = true }
                g = saved.groups[i]
            }
        } else {
            g = Group(id: UUID(), name: clean, color: color ?? nextFreeColor(), pinned: pinned && color != nil ? true : nil, auto: auto ? true : nil)
            saved.groups.append(g)
        }
        saved.windows[String(id)] = g.id
        assignEmoji(id)
        pruneEmptyGroups()
        commit()
        return g
    }

    func unlabel(window id: Int) {
        saved.windows.removeValue(forKey: String(id))
        saved.emoji?.removeValue(forKey: String(id))
        saved.tasks?.removeValue(forKey: String(id))
        saved.autoSkip = Array(Set((saved.autoSkip ?? []) + [String(id)]))
        pruneEmptyGroups()
        commit()
    }

    func rename(_ group: Group, to name: String, color: Int, pinned: Bool = false) {
        guard let i = saved.groups.firstIndex(where: { $0.id == group.id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let other = self.group(named: clean), other.id != group.id {
            // Renaming onto an existing name merges the two groups.
            for (k, v) in saved.windows where v == group.id { saved.windows[k] = other.id }
            if let j = saved.groups.firstIndex(where: { $0.id == other.id }) { saved.groups[j].color = color }
        } else {
            saved.groups[i].name = clean
            saved.groups[i].auto = nil
            if pinned || color != saved.groups[i].color { saved.groups[i].color = color }
            if pinned { saved.groups[i].pinned = true }
        }
        pruneEmptyGroups()
        commit()
    }

    func setColor(_ group: Group, _ color: Int) {
        guard let i = saved.groups.firstIndex(where: { $0.id == group.id }) else { return }
        saved.groups[i].color = color
        saved.groups[i].pinned = true
        commit()
    }

    func dissolve(_ group: Group) {
        let ids = saved.windows.filter { $0.value == group.id }.map { $0.key }
        saved.autoSkip = Array(Set((saved.autoSkip ?? []) + ids))
        saved.windows = saved.windows.filter { $0.value != group.id }
        pruneEmptyGroups()
        commit()
    }

    /// Drops windows that no longer exist in Terminal.
    func keepOnly(windows alive: Set<Int>) {
        let before = saved.windows.count
        saved.windows = saved.windows.filter { alive.contains(Int($0.key) ?? -1) }
        saved.originalBackground = saved.originalBackground.filter { alive.contains(Int($0.key) ?? -1) }
        saved.emoji = saved.emoji?.filter { alive.contains(Int($0.key) ?? -1) }
        saved.tasks = saved.tasks?.filter { alive.contains(Int($0.key) ?? -1) }
        saved.autoSkip = saved.autoSkip?.filter { alive.contains(Int($0) ?? -1) }
        if saved.windows.count != before { pruneEmptyGroups(); commit() }
    }

    func original(for id: Int) -> [Int]? { saved.originalBackground[String(id)] }
    func setOriginal(_ rgb: [Int]?, for id: Int) {
        saved.originalBackground[String(id)] = rgb
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: url, options: .atomic) }
    }

    private func pruneEmptyGroups() {
        let used = Set(saved.windows.values)
        saved.groups.removeAll { !used.contains($0.id) }
    }
}
