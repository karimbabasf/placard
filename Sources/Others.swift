import AppKit
import ApplicationServices
import Darwin

/// Terminals other than Terminal.app (Ghostty, iTerm2, WezTerm, kitty, ...).
///
/// They have no shared scripting interface, so Placard reads them through
/// Accessibility (titles, screen text, raise, move) and paints them with escape
/// codes written to their ttys: OSC 11 sets the background, OSC 10 the text,
/// OSC 111 and 110 put the theme's own colors back. Window to tty comes from the
/// app's AppleScript where it has one (Ghostty, iTerm2), else from the process
/// tree when the app has a single window.
enum Others {
    static let bundleIDs = [
        "com.mitchellh.ghostty", "com.googlecode.iterm2", "com.github.wez.wezterm", "net.kovidgoyal.kitty",
        "org.alacritty", "io.alacritty", "dev.warp.Warp-Stable", "co.zeit.hyper", "org.tabby", "com.raphaelamorim.rio",
    ]

    struct Win {
        let id: Int
        let pid: pid_t
        let bundle: String
        var title: String
        var ttys: [String]
        var prompt: Bool
    }

    /// Last poll, by CoreGraphics window id. Behind a lock, never `queue.sync`:
    /// the main thread must not wait out a poll.
    nonisolated(unsafe) private static var known_: [Int: Win] = [:]
    private static let lock = NSLock()
    private static var known: [Int: Win] {
        get { lock.lock(); defer { lock.unlock() }; return known_ }
        set { lock.lock(); known_ = newValue; lock.unlock() }
    }
    /// What Placard last painted on each tty, so a tint is written once, not every poll.
    nonisolated(unsafe) private static var painted: [String: [Int]] = [:]
    nonisolated(unsafe) private static var bases: [String: [Int]] = [:]

    static let queue = DispatchQueue(label: "placard.others")

    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func isOther(_ id: Int) -> Bool { known[id] != nil }

    // MARK: reading

    /// Title, busy flag, prompt flag and ttys of every window of every running
    /// non-Terminal terminal. Runs on `queue`; completion on the main actor.
    static func poll(_ completion: @escaping @MainActor ([Int: TerminalScript.Info]) -> Void) {
        let apps = Windows.apps.filter { $0.bundleIdentifier != Windows.bundleID }
        guard !apps.isEmpty else { Task { @MainActor in completion([:]) }; return }
        queue.async {
            var next: [Int: Win] = [:]
            let procs = Procs.all()
            for app in apps {
                guard let bundle = app.bundleIdentifier else { continue }
                let pid = app.processIdentifier
                let scripted = scriptedWindows(bundle: bundle)
                let wins = axWindows(pid)
                if wins.isEmpty {
                    // No Accessibility: on-screen windows front to back, titled and
                    // matched to the app's own list by order. No screen text, so no flash.
                    let cg = cgWindows(pid)
                    for (i, id) in cg.enumerated() {
                        let s = i < scripted.count && scripted.count == cg.count ? scripted[i] : nil
                        let ttys = s?.ttys ?? (cg.count == 1 ? procs.ttys(under: pid) : [])
                        next[id] = Win(id: id, pid: pid, bundle: bundle, title: s?.title ?? "", ttys: ttys, prompt: false)
                    }
                    continue
                }
                let ttyMap = match(scripted, to: wins.map { ($0.id, $0.title) })
                let fallback = wins.count == 1 ? procs.ttys(under: pid) : []
                for w in wins {
                    let ttys = ttyMap[w.id] ?? fallback
                    let prompt = w.title.unicodeScalars.contains(TerminalScript.idleGlyph) && screenText(w.el).contains(where: Prompts.isClaudePrompt)
                    next[w.id] = Win(id: w.id, pid: pid, bundle: bundle, title: w.title, ttys: ttys, prompt: prompt)
                }
            }
            known = next
            var out: [Int: TerminalScript.Info] = [:]
            for (id, w) in next {
                let busy = w.ttys.contains { procs.busy(tty: $0) }
                out[id] = TerminalScript.Info(title: w.title, bg: currentBackground(w), busy: busy, prompt: w.prompt, tty: w.ttys.first)
            }
            Task { @MainActor in completion(out) }
        }
    }

    /// The quick look that stops a flash: title and prompt flag of these windows only.
    static func watch(_ ids: [Int], _ completion: @escaping @Sendable ([Int: (title: String, prompt: Bool)]) -> Void) {
        queue.async {
            var out: [Int: (title: String, prompt: Bool)] = [:]
            for id in ids {
                guard let w = known[id], let el = element(pid: w.pid, id: id) else { continue }
                let title = string(el, kAXTitleAttribute) ?? w.title
                let prompt = title.unicodeScalars.contains(TerminalScript.idleGlyph) && screenText(el).contains(where: Prompts.isClaudePrompt)
                out[id] = (title, prompt)
            }
            completion(out)
        }
    }

    static func window(forTTY tty: String) -> Int? {
        known.values.first { $0.ttys.contains(tty) }?.id
    }

    // MARK: colors

    /// The theme background Placard tints over. It can't be read back from a
    /// tty, so it comes from the app: Ghostty's resolved config, iTerm2's
    /// session color, else a plain dark gray.
    private static func base(_ w: Win) -> [Int] {
        if let b = bases[w.bundle] { return b }
        var b: [Int]?
        if w.bundle == "com.mitchellh.ghostty" { b = ghosttyBackground() }
        if w.bundle == "com.googlecode.iterm2" {
            b = osascript("tell application id \"com.googlecode.iterm2\" to get background color of current session of current window")
                .flatMap { s in let v = s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }; return v.count == 3 ? v : nil }
        }
        let value = b ?? [0x1e1e, 0x1e1e, 0x2020]
        bases[w.bundle] = value
        return value
    }

    private static func currentBackground(_ w: Win) -> [Int] {
        // A tty Placard hasn't painted shows the theme background.
        if let first = w.ttys.first, w.ttys.allSatisfy({ painted[$0] == painted[first] }), let p = painted[first] { return p }
        return base(w)
    }

    /// The user's background, else their theme's, else Ghostty's default.
    private static func ghosttyBackground() -> [Int]? {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") else { return nil }
        func config(_ args: [String]) -> [String: String] {
            let p = Process()
            p.executableURL = app.appendingPathComponent("Contents/MacOS/ghostty")
            p.arguments = ["+show-config"] + args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            guard (try? p.run()) != nil else { return [:] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            var map: [String: String] = [:]
            for line in (String(data: data, encoding: .utf8) ?? "").split(separator: "\n") {
                let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2, map[kv[0]] == nil { map[kv[0]] = kv[1] }
            }
            return map
        }
        let user = config([])
        if let b = user["background"].flatMap(parseHex) { return b }
        if var theme = user["theme"], !theme.isEmpty {
            // "light:A,dark:B" picks by the system appearance
            if theme.contains(":") {
                let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
                let pairs = Dictionary(theme.split(separator: ",").compactMap { part -> (String, String)? in
                    let kv = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    return kv.count == 2 ? (kv[0], kv[1]) : nil
                }, uniquingKeysWith: { a, _ in a })
                theme = pairs[dark ? "dark" : "light"] ?? theme
            }
            let dirs = [app.appendingPathComponent("Contents/Resources/ghostty/themes").path,
                        NSHomeDirectory() + "/.config/ghostty/themes"]
            for d in dirs {
                guard let text = try? String(contentsOfFile: d + "/" + theme, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n") where line.hasPrefix("background") {
                    let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if kv.count == 2, kv[0] == "background", let b = parseHex(kv[1]) { return b }
                }
            }
        }
        return config(["--default"])["background"].flatMap(parseHex)
    }

    static func parseHex(_ s: String) -> [Int]? {
        let h = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
        return [(v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff].map { $0 * 257 }
    }

    private static func osc(_ code: Int, _ rgb: [Int]) -> String {
        String(format: "\u{1b}]%d;rgb:%04x/%04x/%04x\u{1b}\\", code, rgb[0] & 0xffff, rgb[1] & 0xffff, rgb[2] & 0xffff)
    }
    private static let resetBackground = "\u{1b}]111\u{1b}\\"
    private static let resetText = "\u{1b}]110\u{1b}\\"

    static func setBackground(_ id: Int, _ rgb: [Int]) {
        guard rgb.count == 3 else { return }
        queue.async {
            guard let w = known[id] else { return }
            for t in w.ttys where painted[t] != rgb {
                TTY.write(t, osc(11, rgb))
                painted[t] = rgb
            }
        }
    }

    /// Theme colors back: the escape code reset, not a guessed color.
    static func resetColors(_ id: Int, bg: [Int]?, completion: (@MainActor () -> Void)? = nil) {
        queue.async {
            if let w = known[id] {
                for t in w.ttys {
                    if let bg, bg.count == 3, bg != base(w) { TTY.write(t, resetText + osc(11, bg)); painted[t] = bg }
                    else { TTY.write(t, resetText + resetBackground); painted[t] = nil }
                }
            }
            if let completion { Task { @MainActor in completion() } }
        }
    }

    final class Flash: FlashRun, @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled_ = false
        var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled_ }
        func cancel() { lock.lock(); cancelled_ = true; lock.unlock() }
    }

    /// Same Christmas cycle as Terminal's, written straight to the window's ttys.
    static func haywire(_ id: Int, done: @escaping @MainActor () -> Void) -> FlashRun {
        let flash = Flash()
        let ttys = known[id]?.ttys ?? []
        DispatchQueue.global(qos: .userInitiated).async {
            outer: for _ in 0..<2 {
                for f in TerminalScript.christmas {
                    if flash.cancelled { break outer }
                    for t in ttys { TTY.write(t, osc(11, f.0) + osc(10, f.1)) }
                    usleep(125_000)
                }
            }
            queue.async { for t in ttys { painted[t] = nil } }
            Task { @MainActor in done() }
        }
        return flash
    }

    // MARK: windows

    static func raise(_ ids: [Int]) {
        queue.async {
            var activate = Set<pid_t>()
            for id in ids.reversed() {
                guard let w = known[id], let el = element(pid: w.pid, id: id) else { continue }
                AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementPerformAction(el, kAXRaiseAction as CFString)
                activate.insert(w.pid)
            }
            DispatchQueue.main.async { for pid in activate { NSRunningApplication(processIdentifier: pid)?.activate() } }
        }
    }

    static func setBounds(_ items: [(Int, CGRect)]) {
        queue.async {
            for (id, r) in items {
                guard let w = known[id], let el = element(pid: w.pid, id: id) else { continue }
                var origin = r.origin, size = r.size
                if let v = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v) }
                if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v) }
            }
        }
        raise(items.map { $0.0 })
    }

    static func drain() {
        queue.sync {}
        TTY.queue.sync {}
    }

    // MARK: Accessibility

    private struct AXWin { let id: Int; let el: AXUIElement; let title: String }

    private static func axWindows(_ pid: pid_t) -> [AXWin] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success, let list = v as? [AXUIElement] else { return [] }
        return list.compactMap { el in
            var cg: CGWindowID = 0
            guard _AXUIElementGetWindow(el, &cg) == .success, cg != 0 else { return nil }
            if let sub = string(el, kAXSubroleAttribute), sub != (kAXStandardWindowSubrole as String) { return nil }
            return AXWin(id: Int(cg), el: el, title: string(el, kAXTitleAttribute) ?? "")
        }
    }

    private static func cgWindows(_ pid: pid_t) -> [Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
                  r.height > 60, r.width > 120 else { return nil }
            return w[kCGWindowNumber as String] as? Int
        }
    }

    private static func element(pid: pid_t, id: Int) -> AXUIElement? {
        axWindows(pid).first { $0.id == id }?.el
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    /// The tail of every terminal surface's visible text in a window (splits
    /// give several). Terminals expose it as an AXTextArea value.
    private static func screenText(_ window: AXUIElement) -> [String] {
        var out: [String] = []
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var seen = 0
        while !queue.isEmpty && seen < 300 {
            let (el, depth) = queue.removeFirst()
            seen += 1
            if string(el, kAXRoleAttribute) == (kAXTextAreaRole as String), let text = string(el, kAXValueAttribute) {
                out.append(String(text.suffix(3000)))
                continue
            }
            guard depth < 10 else { continue }
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success, let kids = v as? [AXUIElement] {
                queue.append(contentsOf: kids.map { ($0, depth + 1) })
            }
        }
        return out
    }

    // MARK: window to tty

    /// Ghostty and iTerm2 list their windows front to back with a title and the
    /// ttys inside. Match them to CoreGraphics windows by title; a single
    /// leftover on each side is matched by elimination.
    private static func scriptedWindows(bundle: String) -> [(title: String, ttys: [String])] {
        let src: String
        switch bundle {
        case "com.mitchellh.ghostty":
            src = """
            set T to character id 9
            set NL to character id 10
            tell application id "com.mitchellh.ghostty"
              set out to ""
              repeat with w in windows
                try
                  set ts to ""
                  repeat with t in terminals of w
                    set ts to ts & (tty of t) & ","
                  end repeat
                  set out to out & (name of w) & T & ts & NL
                end try
              end repeat
              return out
            end tell
            """
        case "com.googlecode.iterm2":
            src = """
            set T to character id 9
            set NL to character id 10
            tell application id "com.googlecode.iterm2"
              set out to ""
              repeat with w in windows
                try
                  set ts to ""
                  repeat with tb in tabs of w
                    repeat with s in sessions of tb
                      set ts to ts & (tty of s) & ","
                    end repeat
                  end repeat
                  set out to out & (name of w) & T & ts & NL
                end try
              end repeat
              return out
            end tell
            """
        default: return []
        }
        guard let text = osascript(src) else { return [] }
        return text.split(separator: "\n").map { line in
            let parts = line.components(separatedBy: "\t")
            return (parts[0], (parts.count > 1 ? parts[1] : "").split(separator: ",").map(String.init).filter(TTY.valid))
        }
    }

    private static func match(_ list: [(title: String, ttys: [String])], to windows: [(id: Int, title: String)]) -> [Int: [String]] {
        var scripted = list
        var out: [Int: [String]] = [:]
        var left: [(id: Int, title: String)] = []
        for w in windows {
            if let i = scripted.firstIndex(where: { $0.title == w.title }) { out[w.id] = scripted.remove(at: i).ttys }
            else { left.append(w) }
        }
        if left.count == 1, scripted.count == 1 { out[left[0].id] = scripted[0].ttys }
        return out
    }

    private static func osascript(_ src: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", src]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        guard (try? p.run()) != nil else { return nil }
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: watchdog)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        watchdog.cancel()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            Log.write("osascript (others) \(p.terminationStatus): \(msg.prefix(200))")
            return nil
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines)
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

protocol FlashRun: AnyObject { func cancel() }
extension TerminalScript.Flash: FlashRun {}

enum Prompts {
    static let markers = ["Do you want to", "Would you like to proceed", "Enter to select", "Esc to cancel"]
    static func isClaudePrompt(_ text: String) -> Bool { markers.contains { text.contains($0) } }
}

/// Writes escape codes to a tty: the terminal on its other end paints them.
enum TTY {
    static let queue = DispatchQueue(label: "placard.tty")

    static func valid(_ path: String) -> Bool {
        path.range(of: "^/dev/ttys[0-9]+$", options: .regularExpression) != nil
    }

    static func write(_ path: String, _ text: String) {
        guard valid(path) else { return }
        queue.async {
            let fd = open(path, O_WRONLY | O_NOCTTY | O_NONBLOCK)
            guard fd >= 0 else { return }
            // One write call per sequence, so it can't split around another program's output.
            text.utf8CString.withUnsafeBufferPointer { b in _ = Darwin.write(fd, b.baseAddress, b.count - 1) }
            close(fd)
        }
    }
}

/// The process table, read once per poll: which ttys a terminal owns, whether a
/// tty runs anything beyond its shell, and where its agent was started.
struct Procs {
    struct P { let pid: pid_t; let ppid: pid_t; let pgid: pid_t; let tpgid: pid_t; let tty: String?; let comm: String }
    let list: [P]

    static func all() -> Procs {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return Procs(list: []) }
        let stride = MemoryLayout<kinfo_proc>.stride
        var buf = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = buf.count * stride
        guard sysctl(&mib, 4, &buf, &size, nil, 0) == 0 else { return Procs(list: []) }
        let n = size / stride
        var out: [P] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let k = buf[i]
            let dev = k.kp_eproc.e_tdev
            var tty: String?
            if dev != -1, dev != 0, let name = devname(dev, S_IFCHR) {
                tty = "/dev/" + String(cString: name)
            }
            let comm = withUnsafeBytes(of: k.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            out.append(P(pid: k.kp_proc.p_pid, ppid: k.kp_eproc.e_ppid, pgid: k.kp_eproc.e_pgid, tpgid: k.kp_eproc.e_tpgid, tty: tty, comm: comm))
        }
        return Procs(list: out)
    }

    /// Every tty held by a descendant of `root`.
    func ttys(under root: pid_t) -> [String] {
        var parent: [pid_t: pid_t] = [:]
        for p in list { parent[p.pid] = p.ppid }
        func descends(_ pid: pid_t) -> Bool {
            var cur = pid, hops = 0
            while cur > 1 && hops < 32 { if cur == root { return true }; cur = parent[cur] ?? 0; hops += 1 }
            return false
        }
        return Array(Set(list.compactMap { p in p.tty.flatMap { TTY.valid($0) && descends(p.pid) ? $0 : nil } })).sorted()
    }

    private static let shells: Set<String> = ["login", "zsh", "-zsh", "bash", "-bash", "fish", "-fish", "sh", "-sh", "nu", "tcsh", "csh", "dash", "xonsh"]

    func busy(tty: String) -> Bool {
        list.contains { $0.tty == tty && !Self.shells.contains($0.comm) }
    }

    /// Where the agent on this tty works: Claude's own cwd when it runs there,
    /// else the foreground process's.
    func cwd(tty: String) -> String? {
        let on = list.filter { $0.tty == tty }
        let pick = on.first { $0.comm == "claude" } ?? on.first { $0.pgid == $0.tpgid && !Self.shells.contains($0.comm) } ?? on.first { $0.pgid == $0.tpgid }
        guard let pid = pick?.pid else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : path
    }
}

/// One front door for every terminal: Terminal.app goes through its AppleScript,
/// everything else through `Others`.
@MainActor
enum Backend {
    private final class Merge {
        var map: [Int: TerminalScript.Info] = [:]
        var left = 2
    }

    static func titles(_ completion: @escaping @MainActor ([Int: TerminalScript.Info]) -> Void) {
        let m = Merge()
        let land: @MainActor ([Int: TerminalScript.Info]) -> Void = { part in
            m.map.merge(part) { a, _ in a }
            m.left -= 1
            if m.left == 0 { completion(m.map) }
        }
        TerminalScript.titles(land)
        Others.poll(land)
    }

    /// nil when Terminal's script failed; windows that closed are absent.
    static func watch(_ ids: [Int], _ completion: @escaping @MainActor ([Int: (title: String, prompt: Bool)]?) -> Void) {
        let other = ids.filter(Others.isOther)
        let term = ids.filter { !Others.isOther($0) }
        Others.watch(other) { seen in
            Task { @MainActor in
                guard !term.isEmpty else { completion(seen); return }
                TerminalScript.watch(term) { t in completion(t.map { $0.merging(seen) { a, _ in a } }) }
            }
        }
    }

    static func raise(_ ids: [Int]) {
        TerminalScript.raise(ids.filter { !Others.isOther($0) })
        let other = ids.filter(Others.isOther)
        if !other.isEmpty { Others.raise(other) }
    }

    static func setBounds(_ items: [(Int, CGRect)]) {
        let term = items.filter { !Others.isOther($0.0) }
        let other = items.filter { Others.isOther($0.0) }
        if !term.isEmpty { TerminalScript.setBounds(term) }
        if !other.isEmpty { Others.setBounds(other) }
    }

    static func setBackground(_ id: Int, _ rgb: [Int]) {
        Others.isOther(id) ? Others.setBackground(id, rgb) : TerminalScript.setBackground(id, rgb)
    }

    /// Back to the window's own background, the one it had before Placard.
    static func resetBackground(_ id: Int, _ original: [Int]) {
        Others.isOther(id) ? Others.resetColors(id, bg: nil) : TerminalScript.setBackground(id, original)
    }

    static func haywire(_ id: Int, done: @escaping @MainActor () -> Void) -> FlashRun {
        Others.isOther(id) ? Others.haywire(id, done: done) : TerminalScript.haywire(id, done: done)
    }

    static func restoreColors(_ id: Int, bg: [Int]?, completion: @escaping @MainActor () -> Void) {
        if Others.isOther(id) { Others.resetColors(id, bg: bg, completion: completion) }
        else { TerminalScript.restoreColors(id, bg: bg) { _ in completion() } }
    }

    static func window(forTTY tty: String, _ completion: @escaping @MainActor (Int?) -> Void) {
        if let id = Others.window(forTTY: tty) { completion(id); return }
        TerminalScript.window(forTTY: tty, completion)
    }

    nonisolated static func drain() {
        TerminalScript.drain()
        Others.drain()
    }
}
