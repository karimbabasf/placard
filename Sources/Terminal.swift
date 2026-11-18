import AppKit
import CoreGraphics

enum WorkState { case none, running, working, yourTurn, needsYou }

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Placard.log")
    static func write(_ line: String) {
        let text = "\(Date()) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(text.data(using: .utf8)!); try? h.close() }
        else { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }
}

struct TermWindow {
    let id: Int
    let frame: CGRect   // global, top-left origin (CoreGraphics space)
}

enum Windows {
    static let bundleID = "com.apple.Terminal"

    /// runningApplications(withBundleIdentifier:) sometimes comes back empty for a
    /// moment while Terminal is running, which used to tear down every strip.
    /// Keep the process until it has really exited.
    private static var cached: NSRunningApplication?
    static var terminalApp: NSRunningApplication? {
        if let c = cached, !c.isTerminated, kill(c.processIdentifier, 0) == 0 { return c }
        cached = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        return cached
    }

    /// On-screen windows, front to back: the Terminal ones, plus every window id in z-order.
    static func snapshot() -> (terminal: [TermWindow], order: [Int]) {
        guard let pid = terminalApp?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return ([], []) }
        var term: [TermWindow] = []
        var order: [Int] = []
        for w in list {
            guard let num = w[kCGWindowNumber as String] as? Int else { continue }
            order.append(num)
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b),
                  r.height > 60, r.width > 120
            else { continue }
            term.append(TermWindow(id: num, frame: r))
        }
        return (term, order)
    }

    /// Every Terminal window that still exists, on any Space, minimized or not.
    static func allTerminalIDs() -> Set<Int>? {
        guard let pid = terminalApp?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        var ids = Set<Int>()
        for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
            if let n = w[kCGWindowNumber as String] as? Int { ids.insert(n) }
        }
        return ids
    }

    /// Cheap read of just these windows: frame when on screen, nothing otherwise.
    static func frames(for ids: [Int]) -> [Int: CGRect] {
        guard !ids.isEmpty else { return [:] }
        var ptrs: [UnsafeRawPointer?] = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let arr = CFArrayCreate(nil, &ptrs, ptrs.count, nil),
              let list = CGWindowListCreateDescriptionFromArray(arr) as? [[String: Any]] else { return [:] }
        var out: [Int: CGRect] = [:]
        for w in list {
            guard let id = w[kCGWindowNumber as String] as? Int,
                  (w[kCGWindowIsOnscreen as String] as? Bool) == true,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b) else { continue }
            out[id] = r
        }
        return out
    }

    static func frontTerminalWindow() -> TermWindow? { snapshot().terminal.first }

    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func cocoaRect(_ cg: CGRect) -> NSRect {
        NSRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
    }

    static func cgRect(_ ns: NSRect) -> CGRect {
        CGRect(x: ns.minX, y: primaryHeight - ns.maxY, width: ns.width, height: ns.height)
    }
}

/// Talks to Terminal over Apple Events through osascript, off the main thread.
enum TerminalScript {
    private static let queue = DispatchQueue(label: "placard.osascript")

    static func run(_ source: String, completion: (@MainActor (String?) -> Void)? = nil) {
        guard Windows.terminalApp != nil else {
            if let completion { Task { @MainActor in completion(nil) } }
            return
        }
        queue.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", source]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            var result: String?
            do {
                try p.run()
                let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: watchdog)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus == 0 { result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) }
                else if let errPipe = p.standardError as? Pipe {
                    let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    Log.write("osascript \(p.terminationStatus): \(msg.prefix(300))")
                }
            } catch {}
            if let completion { Task { @MainActor in completion(result) } }
        }
    }

    static func list(_ ints: [Int]) -> String { "{" + ints.map(String.init).joined(separator: ", ") + "}" }

    struct Info { let title: String; let bg: [Int]; let busy: Bool; let prompt: Bool; let fg: [Int]; let bold: [Int] }

    /// Each window's id, title, busy flag and first-tab background color.
    static func titles(_ completion: @escaping @MainActor ([Int: Info]) -> Void) {
        let src = """
        set T to character id 9
        set NL to character id 10
        tell application "Terminal"
          set out to ""
          repeat with w in windows
            try
              set flag to "0"
              if (name of w) contains (character id 10035) then
                set c to contents of selected tab of w
                if length of c > 3000 then set c to text -3000 thru -1 of c
                if c contains "Do you want to" or c contains "Would you like to proceed" or c contains "Enter to select" or c contains "Esc to cancel" then set flag to "1"
              end if
              set bg to background color of tab 1 of w
              set fg to normal text color of tab 1 of w
              set bd to bold text color of tab 1 of w
              set out to out & (id of w) & T & (name of w) & T & (item 1 of bg) & "," & (item 2 of bg) & "," & (item 3 of bg) & T & (busy of selected tab of w) & T & flag & T & (item 1 of fg) & "," & (item 2 of fg) & "," & (item 3 of fg) & T & (item 1 of bd) & "," & (item 2 of bd) & "," & (item 3 of bd) & NL
            end try
          end repeat
          return out
        end tell
        """
        run(src) { text in
            var map: [Int: Info] = [:]
            for line in (text ?? "").split(separator: "\n") {
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 7, let id = Int(parts[0]) else { continue }
                let bg = parts[2].split(separator: ",").compactMap { Int($0) }
                let fg = parts[5].split(separator: ",").compactMap { Int($0) }
                let bold = parts[6].split(separator: ",").compactMap { Int($0) }
                map[id] = Info(title: parts[1], bg: bg, busy: parts[3] == "true", prompt: parts[4] == "1", fg: fg, bold: bold)
            }
            completion(map)
        }
    }

    static func raise(_ ids: [Int]) {
        guard !ids.isEmpty else { return }
        // Last one first, so the first window ends on top.
        let src = """
        tell application "Terminal"
          repeat with i in \(list(ids.reversed()))
            try
              set miniaturized of window id i to false
              set index of window id i to 1
            end try
          end repeat
          activate
        end tell
        """
        run(src)
    }

    static func setBounds(_ items: [(Int, CGRect)]) {
        let lines = items.map { id, r in
            "try\nset bounds of window id \(id) to {\(Int(r.minX)), \(Int(r.minY)), \(Int(r.maxX)), \(Int(r.maxY))}\nend try"
        }.joined(separator: "\n")
        run("tell application \"Terminal\"\n\(lines)\nend tell") { _ in raise(items.map { $0.0 }) }
    }

    static func setBackground(_ id: Int, _ rgb: [Int]) {
        guard rgb.count == 3 else { return }
        let c = "{\(rgb[0]), \(rgb[1]), \(rgb[2])}"
        let src = """
        tell application "Terminal"
          try
            repeat with t in tabs of window id \(id)
              if background color of t is not \(c) then set background color of t to \(c)
            end repeat
          end try
        end tell
        """
        run(src)
    }

    /// Christmas frames: (background, text). Deep backgrounds, bright letters.
    private static let christmasRaw: [[Double]] = [
        [0.62, 0.04, 0.10, 0.55, 1.00, 0.62],
        [0.03, 0.42, 0.17, 1.00, 0.86, 0.25],
        [0.55, 0.38, 0.00, 1.00, 1.00, 1.00],
        [0.04, 0.26, 0.12, 1.00, 0.32, 0.36],
        [0.70, 0.08, 0.14, 1.00, 1.00, 1.00],
        [0.05, 0.50, 0.22, 1.00, 0.40, 0.42],
    ]
    /// Blended frames between the pairs, so colors flow instead of strobing.
    static let christmas: [([Int], [Int])] = {
        let steps = 5
        var out: [([Int], [Int])] = []
        for i in 0..<christmasRaw.count {
            let a = christmasRaw[i], b = christmasRaw[(i + 1) % christmasRaw.count]
            for k in 0..<steps {
                let t = Double(k) / Double(steps)
                let v = zip(a, b).map { Int((($0 * (1 - t)) + $1 * t) * 65535) }
                out.append((Array(v[0..<3]), Array(v[3..<6])))
            }
        }
        return out
    }()

    private static let haywireQueue = DispatchQueue(label: "placard.haywire", attributes: .concurrent)

    /// One ~1.3 s run of the color cycle on every tab of a window; the manager
    /// starts the next run while the agent still needs you.
    static func haywire(_ id: Int, done: @escaping @MainActor () -> Void) {
        func c(_ v: [Int]) -> String { "{\(v[0]), \(v[1]), \(v[2])}" }
        let frames = christmas.map { "{\(c($0.0)), \(c($0.1))}" }.joined(separator: ", ")
        let src = """
        tell application "Terminal"
          try
            set w to window id \(id)
            repeat 2 times
              repeat with f in {\(frames)}
                repeat with t in tabs of w
                  set background color of t to item 1 of f
                  set normal text color of t to item 2 of f
                  set bold text color of t to item 2 of f
                end repeat
                delay 0.05
              end repeat
            end repeat
          end try
        end tell
        """
        haywireQueue.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", src]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
            Task { @MainActor in done() }
        }
    }

    static func setColors(_ id: Int, bg: [Int], fg: [Int], bold: [Int]) {
        guard bg.count == 3, fg.count == 3, bold.count == 3 else { return }
        func c(_ v: [Int]) -> String { "{\(v[0]), \(v[1]), \(v[2])}" }
        run("""
        tell application "Terminal"
          try
            repeat with t in tabs of window id \(id)
              set background color of t to \(c(bg))
              set normal text color of t to \(c(fg))
              set bold text color of t to \(c(bold))
            end repeat
          end try
        end tell
        """)
    }

    static func window(forTTY tty: String, _ completion: @escaping @MainActor (Int?) -> Void) {
        let safe = tty.replacingOccurrences(of: "\"", with: "")
        let src = """
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(safe)" then return id of w
            end repeat
          end repeat
        end tell
        """
        run(src) { completion($0.flatMap { Int($0) }) }
    }

    static let idleGlyph: Unicode.Scalar = "\u{2733}"
    static let workGlyphs = CharacterSet(charactersIn: "\u{25D0}\u{25D1}\u{25D2}\u{25D3}\u{2736}\u{273B}\u{273D}\u{00B7}*")
        .union(CharacterSet(charactersIn: "\u{2800}"..."\u{28FF}"))

    /// Claude Code puts a spinner glyph in the title while it works and a
    /// six-spoke asterisk when it waits for you. Any other busy tab is "running".
    static func state(title: String, busy: Bool, prompt: Bool = false) -> WorkState {
        let parts = title.components(separatedBy: " \u{2014} ")
        for part in parts {
            guard let first = part.trimmingCharacters(in: .whitespaces).unicodeScalars.first else { continue }
            if first == idleGlyph { return prompt ? .needsYou : .yourTurn }
            if workGlyphs.contains(first) { return .working }
        }
        return busy ? .running : .none
    }

    /// Label for a window whose agent just got its first task title: an open group the
    /// title mentions, else the project folder, else the first two real words of the task.
    static func autoName(title: String, groups: [Group]) -> String? {
        let task = subtitle(from: title)
        guard !task.isEmpty, task.caseInsensitiveCompare("Claude Code") != .orderedSame else { return nil }
        let lower = task.lowercased()
        if let g = groups.first(where: { g in
            let n = g.name.lowercased()
            return lower.hasPrefix(n) || lower.contains(" " + n) || lower.contains("(" + n)
        }) { return g.name }
        let dir = title.components(separatedBy: " \u{2014} ").first?.trimmingCharacters(in: .whitespaces) ?? ""
        if !dir.isEmpty, dir != NSUserName(), dir != "~", !dir.hasPrefix("-") { return String(dir.prefix(24)) }
        let stop: Set<String> = ["a", "an", "the", "for", "to", "of", "and", "in", "on", "with", "my", "is", "it", "this", "that", "how", "what", "why"]
        let words = task.split(separator: " ").map(String.init).filter { w in
            !stop.contains(w.lowercased()) && w.rangeOfCharacter(from: .letters) != nil
        }
        guard !words.isEmpty else { return nil }
        return words.prefix(2).map { w in
            w.first.map { $0.isLowercase ? $0.uppercased() + w.dropFirst() : w } ?? w
        }.joined(separator: " ")
    }

    /// Short readable subtitle from a Terminal window title. Terminal joins the
    /// parts with an em dash: directory, task title (Claude Code), process, size.
    static func subtitle(from title: String) -> String {
        var parts = title.components(separatedBy: " \u{2014} ").map { $0.trimmingCharacters(in: .whitespaces) }
        if let last = parts.last, last.range(of: "^\\d+\u{00D7}\\d+$", options: .regularExpression) != nil { parts.removeLast() }
        let glyphs = CharacterSet(charactersIn: "\u{25D0}\u{25D1}\u{25D2}\u{25D3}\u{2733}\u{2736}\u{273B}\u{273D}\u{00B7}\u{2022}* ")
            .union(CharacterSet(charactersIn: "\u{2800}"..."\u{28FF}"))
        if let task = parts.dropFirst().first(where: { $0.unicodeScalars.first.map { glyphs.contains($0) } ?? false }) {
            return task.trimmingCharacters(in: glyphs)
        }
        if parts.count > 1 { return parts[1].trimmingCharacters(in: glyphs) }
        return parts.first ?? ""
    }
}
