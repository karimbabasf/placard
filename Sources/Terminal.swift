import AppKit
import CoreGraphics

enum WorkState { case none, running, working, yourTurn }

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

    static var terminalApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
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

    struct Info { let title: String; let bg: [Int]; let busy: Bool }

    /// Each window's id, title, busy flag and first-tab background color.
    static func titles(_ completion: @escaping @MainActor ([Int: Info]) -> Void) {
        let src = """
        set T to character id 9
        set NL to character id 10
        tell application "Terminal"
          set out to ""
          repeat with w in windows
            try
              set bg to background color of tab 1 of w
              set out to out & (id of w) & T & (name of w) & T & (item 1 of bg) & "," & (item 2 of bg) & "," & (item 3 of bg) & T & (busy of selected tab of w) & NL
            end try
          end repeat
          return out
        end tell
        """
        run(src) { text in
            var map: [Int: Info] = [:]
            for line in (text ?? "").split(separator: "\n") {
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 4, let id = Int(parts[0]) else { continue }
                let bg = parts[2].split(separator: ",").compactMap { Int($0) }
                map[id] = Info(title: parts[1], bg: bg, busy: parts[3] == "true")
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
    static func state(title: String, busy: Bool) -> WorkState {
        let parts = title.components(separatedBy: " \u{2014} ")
        for part in parts {
            guard let first = part.trimmingCharacters(in: .whitespaces).unicodeScalars.first else { continue }
            if first == idleGlyph { return .yourTurn }
            if workGlyphs.contains(first) { return .working }
        }
        return busy ? .running : .none
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
