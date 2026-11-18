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
    static func oklab(_ i: Int) -> (Double, Double, Double) {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r0, g0, b0) = rgb(i)
        let r = lin(r0), g = lin(g0), b = lin(b0)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
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
}

struct Saved: Codable {
    var groups: [Group] = []
    var windows: [String: UUID] = [:]      // Terminal window id -> group id
    var originalBackground: [String: [Int]] = [:]
    var tint: Bool = true
    var didFirstLaunch: Bool = false
    var hidden: Bool? = nil                 // labels turned off, handles stay
    var emoji: [String: String]? = nil      // Terminal window id -> emoji
    var auto: Bool? = nil                   // auto-label agent windows (default on)
    var flash: Bool? = nil                  // Christmas mode when an agent needs you (default on)
    var autoSkip: [String]? = nil           // windows whose label you removed: never auto-label again
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

    func isSkipped(_ id: Int) -> Bool { saved.autoSkip?.contains(String(id)) ?? false }

    func emoji(forWindow id: Int) -> String? { saved.emoji?[String(id)] }

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
    func label(window id: Int, name: String, color: Int?, pinned: Bool = false) -> Group {
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
            g = Group(id: UUID(), name: clean, color: color ?? nextFreeColor(), pinned: pinned && color != nil ? true : nil)
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
