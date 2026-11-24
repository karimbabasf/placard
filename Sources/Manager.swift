import AppKit
import QuartzCore

/// One on-screen window as WindowServer reports it, front to back.
struct SceneWindow {
    let id: Int
    let pid: Int32
    let layer: Int
    let frame: CGRect
}

@MainActor
protocol WindowActions: AnyObject {
    func windowMenu(for window: Int, anchor: CGRect) -> NSMenu
    func renameGroup(of window: Int, anchor: CGRect)
    func renameTask(of window: Int, anchor: CGRect)
    func labelWindow(_ window: Int, anchor: CGRect)
}

/// Clickable piece that sits on the strip's name (or alone in the title bar as a handle).
final class ControlPanel: NSPanel {
    let control = ControlView()
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 22, height: 22),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary, .transient]
        contentView = control
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ControlView: NSView {
    enum Kind: Equatable {
        case name(color: Int, nameEnd: CGFloat, chevronEnd: CGFloat)  // over a visible strip: name, chevron, task text
        case handle(color: Int?, initial: String)  // labels hidden, or window not labeled
    }

    var kind: Kind = .handle(color: nil, initial: "") { didSet { if kind != oldValue { restyle() } } }
    var dark = false { didSet { if dark != oldValue { restyle() } } }
    var onPrimary: (() -> Void)?
    var onMenu: (() -> Void)?
    var onTask: (() -> Void)?
    private var hovering = false { didSet { restyle() } }
    private var hoverX: CGFloat = 0 { didSet { if hovering { restyle() } } }
    private let hoverPad = CALayer()
    private let plus = CAShapeLayer()
    private let letter = CATextLayer()
    private var area: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.magnificationFilter = .nearest
        plus.fillColor = nil
        plus.lineWidth = 1.8
        plus.lineCap = .round
        hoverPad.cornerRadius = 7
        hoverPad.cornerCurve = .continuous
        layer?.addSublayer(hoverPad)
        layer?.addSublayer(plus)
        letter.font = Fonts.geist(12, "SemiBold")
        letter.fontSize = 12
        letter.alignmentMode = .center
        letter.contentsScale = 2
        layer?.addSublayer(letter)
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseMoved(with event: NSEvent) { hoverX = convert(event.locationInWindow, from: nil).x }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch kind {
        case .name(_, let ne, let ce): p.x < ne ? onPrimary?() : (p.x < ce ? onMenu?() : onTask?())
        case .handle(let c, _): c == nil ? onPrimary?() : onMenu?()
        }
    }
    override func rightMouseDown(with event: NSEvent) { onMenu?() }

    override func layout() {
        super.layout()
        restyle()
    }

    private func restyle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let b = bounds
        plus.frame = b
        letter.frame = CGRect(x: 0, y: (b.height - 16) / 2 - 1, width: b.width, height: 16)
        letter.contentsScale = window?.backingScaleFactor ?? 2
        switch kind {
        case .name(let c, let ne, let ce):
            layer?.contents = nil
            layer?.cornerRadius = 7
            layer?.backgroundColor = NSColor.clear.cgColor
            let darkInk = !dark && Palette.all[c].darkText
            // light up only the piece under the pointer: name, chevron, or task text
            let r: CGRect = hoverX < ne ? CGRect(x: 0, y: 0, width: ne, height: b.height)
                : hoverX < ce ? CGRect(x: ne, y: 0, width: ce - ne, height: b.height)
                : CGRect(x: ce, y: 0, width: b.width - ce, height: b.height)
            hoverPad.frame = r.insetBy(dx: 0, dy: 2)
            hoverPad.backgroundColor = (darkInk ? NSColor(white: 0, alpha: 0.12) : NSColor(white: 1, alpha: 0.16)).cgColor
            hoverPad.isHidden = !hovering
            plus.isHidden = true
            letter.isHidden = true
        case .handle(let c, let initial):
            hoverPad.isHidden = true
            layer?.cornerRadius = 6
            if let c {
                layer?.contents = Dither.swatch(size: b.size, color: c, dark: dark)
                layer?.backgroundColor = nil
                layer?.opacity = hovering ? 1 : 0.92
                let isEmoji = initial.unicodeScalars.first.map { $0.properties.isEmoji && $0.value > 0x2000 } ?? false
                letter.string = NSAttributedString(string: initial, attributes: [
                    .font: isEmoji ? (NSFont(name: "AppleColorEmoji", size: 13) ?? .systemFont(ofSize: 13)) : Fonts.geist(12, "SemiBold"),
                    .foregroundColor: Palette.ink(c, dull: false, dark: dark),
                ])
                letter.isHidden = false
                plus.isHidden = true
            } else {
                layer?.contents = nil
                layer?.backgroundColor = NSColor(white: 1, alpha: hovering ? 0.2 : 0.09).cgColor
                layer?.opacity = 1
                let p = CGMutablePath()
                let m = CGPoint(x: b.midX, y: b.midY)
                p.move(to: CGPoint(x: m.x - 4.5, y: m.y)); p.addLine(to: CGPoint(x: m.x + 4.5, y: m.y))
                p.move(to: CGPoint(x: m.x, y: m.y - 4.5)); p.addLine(to: CGPoint(x: m.x, y: m.y + 4.5))
                plus.path = p
                plus.strokeColor = NSColor(white: 1, alpha: hovering ? 0.9 : 0.55).cgColor
                plus.isHidden = false
                letter.isHidden = true
            }
        }
        CATransaction.commit()
    }
}

/// CADisplayLink needs an NSObject target.
final class LinkTarget: NSObject {
    var onFrame: (@MainActor () -> Void)?
    @objc func step(_ link: CADisplayLink) { MainActor.assumeIsolated { onFrame?() } }
}

@MainActor
final class OverlayManager {
    private final class Slot {
        let strip = StripPanel()
        let control = ControlPanel()
        var entered = false
        var stripFrame: NSRect?
        var controlFrame: NSRect?
    }

    weak var actions: WindowActions?
    private var slots: [Int: Slot] = [:]
    private var info: [Int: TerminalScript.Info] = [:]
    private var parsed: [Int: (subtitle: String, state: WorkState)] = [:]
    private var link: CADisplayLink?
    private let linkTarget = LinkTarget()
    private var lastInfoAt: CFTimeInterval = 0
    private var lastKeepAt: CFTimeInterval = 0
    private var lastWatchAt: CFTimeInterval = 0
    private var lastIdleFrame: CFTimeInterval = 0
    /// The window being dragged by its title bar: where it and the mouse were at mouse down.
    private var drag: (id: Int, frame: CGRect, mouse: CGPoint)?
    private var quietUntil = Date.distantPast
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var polling = false
    private var scene_: [SceneWindow] = []
    private var lastScan: CFTimeInterval = 0
    private var scanBurstUntil: CFTimeInterval = 0
    private var lastRaw: [Int: CGRect] = [:]
    private var lastOrder: [Int] = []
    private var menuOpen = false

    static let handleSize: CGFloat = 22

    /// CGWindowListCreate is hidden from Swift but still exported; it returns bare
    /// window ids, which is far cheaper than CGWindowListCopyWindowInfo.
    private typealias ListFn = @convention(c) (CGWindowListOption, CGWindowID) -> Unmanaged<CFArray>?
    private static let listFn: ListFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreate") else { return nil }
        return unsafeBitCast(sym, to: ListFn.self)
    }()

    static func windowOrder() -> [Int] {
        guard let fn = listFn, let arr = fn(.optionOnScreenOnly, kCGNullWindowID)?.takeRetainedValue() else { return [] }
        return (0..<CFArrayGetCount(arr)).map { Int(bitPattern: CFArrayGetValueAtIndex(arr, $0)) }
    }

    func start() {
        // Tick on the display's own refresh (120 Hz on ProMotion), not a 60 Hz
        // timer that drifts against it: the strip moves in the same frame as the window.
        linkTarget.onFrame = { [weak self] in self?.tick() }
        startLink()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startLink() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // With several displays this fires on every click into another display,
            // so never hide here: just rescan, the on-screen check does the rest.
            MainActor.assumeIsolated { self?.burst(0.6) }
        }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.burst(0.5) }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .keyDown]) { [weak self] e in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.burst()
                if e.type == .leftMouseDown { self.beginDrag() }
                if e.type == .leftMouseUp { self.drag = nil }
            }
        }
        // A Placard that was killed mid-flash left these windows in flash colors:
        // the first tick puts them back.
        let stuck = Store.shared.flashing
        if !stuck.isEmpty {
            TerminalScript.killStrayFlashes()
            haywireDirty = Set(stuck)
        }
        refreshInfo()
    }

    /// Full z-order scans are the expensive part: run them in bursts after clicks and
    /// app switches, every frame while a Terminal window moves, and at 8 Hz otherwise.
    func burst(_ seconds: CFTimeInterval = 0.35) {
        let now = CACurrentMediaTime()
        scanBurstUntil = max(scanBurstUntil, now + seconds)
        activeUntil = max(activeUntil, now + 1)
    }
    private var activeUntil: CFTimeInterval = 0

    private func scene() -> [SceneWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let screens = NSScreen.screens.map { Windows.cgRect($0.frame) }
        return list.compactMap { w in
            guard let id = w[kCGWindowNumber as String] as? Int,
                  let pid = w[kCGWindowOwnerPID as String] as? Int32,
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b),
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01
            else { return nil }
            // A window exactly the size of a screen from a non-terminal app is a
            // see-through overlay (agent cursors, screen tools), not a cover.
            if !Windows.pids.contains(pid), screens.contains(r) { return nil }
            return SceneWindow(id: id, pid: pid, layer: layer, frame: r)
        }
    }

    func tick() {
        let store = Store.shared
        let now = CACurrentMediaTime()
        if now - lastInfoAt >= 1.25 { lastInfoAt = now; refreshInfo() }      // titles and status
        if now - lastKeepAt >= 5, let alive = Windows.allTerminalIDs() { lastKeepAt = now; store.keepOnly(windows: alive) }

        let tpids = Windows.pids
        guard !tpids.isEmpty else {
            if !slots.isEmpty { Log.write("slots cleared: no terminal running"); slots.values.forEach { $0.strip.orderOut(nil); $0.control.orderOut(nil) }; slots.removeAll() }
            return
        }
        // Stop a flash the moment its window stops waiting, on screen or not.
        for id in haywireDirty where !wantsFlash(id) {
            if let run = haywireRuns[id] { run.cancel() } else { endHaywire(id) }
        }
        if !haywireDirty.isEmpty && now - lastWatchAt >= 0.25 { lastWatchAt = now; watchFlashing() }   // 4 Hz, only while one flashes

        // Terminal windows = what Terminal's scripting reports (skips its Settings
        // window), plus anything labeled.
        // Full rate only around activity (clicks, keys, drags, moves, reorders);
        // otherwise 15 Hz is plenty and keeps the process near idle.
        if now > activeUntil && NSEvent.pressedMouseButtons == 0 && now - lastIdleFrame < 1.0 / 15 { return }
        lastIdleFrame = now
        let known = Set(info.keys).union(store.labeledWindows)
        var raw = Windows.frames(for: Array(known))
        let moved = raw != lastRaw
        lastRaw = raw
        predictDrag(&raw)
        // Window ids only, no dictionaries: cheap enough to run every frame and
        // catches any z-order change the moment it lands.
        let order = Self.windowOrder()
        let reordered = order != lastOrder
        lastOrder = order
        let dragging = NSEvent.pressedMouseButtons != 0
        if moved || reordered || dragging { activeUntil = now + 1 }
        if moved || reordered || dragging || now < scanBurstUntil || now - lastScan > 0.5 {
            scene_ = scene()
            lastScan = now
        }
        let quiet = Date() < quietUntil
        var index: [Int: Int] = [:]
        for (i, w) in scene_.enumerated() where tpids.contains(w.pid) && raw[w.id] != nil { index[w.id] = i }
        let hidden = store.hidden

        for (id, frame) in raw {
            let slot = slots[id] ?? {
                let s = Slot()
                s.control.control.onPrimary = { [weak self] in self?.primary(id) }
                s.control.control.onMenu = { [weak self] in self?.showMenu(id) }
                s.control.control.onTask = { [weak self] in guard let self else { return }; self.actions?.renameTask(of: id, anchor: self.anchor(id)) }
                slots[id] = s
                return s
            }()
            if quiet { slot.strip.orderOut(nil); slot.control.orderOut(nil); continue }

            // Christmas mode only while the agent waits on you.
            if wantsFlash(id) { startHaywire(id) }

            let group = store.group(forWindow: id)
            let showStrip = group != nil && !hidden
            let stripCG = StripMetrics.frame(for: frame)

            func cuts(for rect: CGRect) -> [CGRect] {
                guard let i = index[id] else { return [] }
                var out: [CGRect] = []
                for o in scene_[..<i] where o.pid != ownPID && o.layer >= 0 && o.layer < 20 {
                    let hit = o.frame.intersection(rect)
                    if !hit.isNull, hit.width > 0, hit.height > 0 {
                        out.append(CGRect(x: hit.minX - rect.minX, y: rect.maxY - hit.maxY, width: hit.width, height: hit.height))
                    }
                }
                return out
            }

            // Strip
            if showStrip, let g = group {
                let p = parsed[id]
                slot.strip.strip.configure(.init(name: g.name, emoji: store.emoji(forWindow: id) ?? "", subtitle: store.task(forWindow: id) ?? p?.subtitle ?? "", color: g.color, state: p?.state ?? .none, dark: Look.dark))
                let target = Windows.cocoaRect(stripCG)
                if slot.stripFrame != target {
                    slot.strip.setFrame(target, display: false)
                    slot.strip.strip.layoutSubtreeIfNeeded()
                    slot.stripFrame = target
                }
                let cs = cuts(for: stripCG)
                slot.strip.strip.setOccluders(cs)
                if !slot.strip.isVisible {
                    Log.write("strip shown \(id)")
                    slot.strip.orderFrontRegardless()
                    if !slot.entered { slot.entered = true; slot.strip.strip.playEntrance() }
                    slot.control.orderOut(nil)      // re-front it above the strip below
                }
            } else if slot.strip.isVisible {
                slot.strip.orderOut(nil)
            }

            // Control: the name area on a strip, or a handle in the title bar.
            slot.control.control.dark = Look.dark
            var controlCG: CGRect
            if showStrip, let g = group {
                slot.strip.strip.layoutSubtreeIfNeeded()
                let r = slot.strip.strip.controlRect
                controlCG = CGRect(x: stripCG.minX + r.minX, y: stripCG.minY + (stripCG.height - r.maxY), width: r.width, height: r.height)
                slot.control.control.kind = .name(color: g.color, nameEnd: slot.strip.strip.nameEnd, chevronEnd: slot.strip.strip.chevronEnd)
            } else {
                let s = Self.handleSize
                // Right end of the title bar: the only part of it nothing else uses.
                controlCG = CGRect(x: frame.maxX - s - 7, y: frame.minY + (StripMetrics.titleBar - s) / 2, width: s, height: s)
                slot.control.control.kind = .handle(color: group?.color, initial: store.emoji(forWindow: id) ?? group.map { String($0.name.prefix(1)).uppercased() } ?? "")
            }
            // Never take a click that belongs to a window in front.
            let covered = !cuts(for: controlCG).isEmpty
            if covered || controlCG.width < 8 {
                if slot.control.isVisible { slot.control.orderOut(nil) }
            } else {
                let target = Windows.cocoaRect(controlCG)
                if slot.controlFrame != target {
                    slot.control.setFrame(target, display: false)
                    slot.controlFrame = target
                }
                if !slot.control.isVisible { slot.control.orderFrontRegardless() }
            }
        }

        for id in raw.keys { missing[id] = 0 }
        for (id, s) in slots where raw[id] == nil {
            // WindowServer sometimes drops a window from one read; only hide after 3 misses.
            missing[id, default: 0] += 1
            if missing[id]! < 3 && known.contains(id) { continue }
            if s.strip.isVisible { Log.write("strip hidden \(id): window off screen"); s.strip.orderOut(nil) }
            if s.control.isVisible { s.control.orderOut(nil) }
            if !known.contains(id) { Log.write("slot dropped \(id)"); slots.removeValue(forKey: id) }
        }
        for (id, s) in slots where store.group(forWindow: id) == nil && s.entered {
            s.entered = false
            restoreBackground(id)
        }
    }

    private var missing: [Int: Int] = [:]

    private func startLink() {
        link?.invalidate()
        let screen = NSScreen.screens.max { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond } ?? NSScreen.main
        guard let l = screen?.displayLink(target: linkTarget, selector: #selector(LinkTarget.step)) else { return }
        l.add(to: .main, forMode: .common)
        link = l
    }

    private static func mouseCG() -> CGPoint {
        let m = NSEvent.mouseLocation
        return CGPoint(x: m.x, y: Windows.primaryHeight - m.y)
    }

    /// A mouse down in a terminal window's title bar may start a drag.
    private func beginDrag() {
        let m = Self.mouseCG()
        let front = scene_.first { $0.frame.contains(m) && $0.pid != ownPID && $0.layer == 0 }
        guard let w = front, let f = lastRaw[w.id], m.y - f.minY < StripMetrics.titleBar + 6 else { drag = nil; return }
        drag = (w.id, f, m)
    }

    /// WindowServer reports a dragged window's frame a frame or two late. The
    /// mouse is current, and a title bar drag moves the window by exactly the
    /// mouse's travel, so place it from the mouse. A snap, a clamp at the menu
    /// bar or any resize falls back to the reported frame.
    private func predictDrag(_ raw: inout [Int: CGRect]) {
        guard let d = drag, NSEvent.pressedMouseButtons & 1 != 0, let r = raw[d.id],
              r.size == d.frame.size, r.origin != d.frame.origin else { return }
        let m = Self.mouseCG()
        var p = d.frame.offsetBy(dx: m.x - d.mouse.x, dy: m.y - d.mouse.y)
        // macOS keeps the title bar below the menu bar.
        if let s = NSScreen.screens.first(where: { Windows.cgRect($0.frame).contains(m) }) {
            p.origin.y = max(p.origin.y, Windows.cgRect(s.visibleFrame).minY)
        }
        if abs(p.minX - r.minX) < 160 && abs(p.minY - r.minY) < 160 { raw[d.id] = p }
    }

    private func cutsFor(_ id: Int, _ rect: CGRect, _ index: [Int: Int]) -> [CGRect] {
        guard let i = index[id] else { return [] }
        var out: [CGRect] = []
        for o in scene_[..<i] where o.pid != ownPID && o.layer >= 0 && o.layer < 20 {
            let hit = o.frame.intersection(rect)
            if !hit.isNull, hit.width > 0, hit.height > 0 {
                out.append(CGRect(x: hit.minX - rect.minX, y: rect.maxY - hit.maxY, width: hit.width, height: hit.height))
            }
        }
        return out
    }

    private func anchor(_ id: Int) -> CGRect { lastRaw[id] ?? .zero }

    private func primary(_ id: Int) {
        // Names this window only: a new name starts a new group, an existing one joins it.
        // Renaming the whole group lives in the menu.
        actions?.labelWindow(id, anchor: anchor(id))
    }

    private func showMenu(_ id: Int) {
        guard let actions, let slot = slots[id], !menuOpen else { return }
        let menu = actions.windowMenu(for: id, anchor: anchor(id))
        menuOpen = true
        let v = slot.control.control
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -6), in: v)
        menuOpen = false
        burst()
    }

    func state(for id: Int) -> (subtitle: String, state: WorkState) {
        let p = parsed[id] ?? ("", .none)
        return (Store.shared.task(forWindow: id) ?? p.subtitle, p.state)
    }
    func terminalTask(for id: Int) -> String { parsed[id]?.subtitle ?? "" }

    func refreshInfo() {
        guard !polling, !Windows.pids.isEmpty else { return }
        polling = true
        let began = CACurrentMediaTime()
        Backend.titles { [weak self] map in
            guard let self else { return }
            self.polling = false
            self.info = map
            self.pollBegan = began
            var next = map.mapValues { (subtitle: TerminalScript.subtitle(from: $0.title), state: TerminalScript.state(title: $0.title, busy: $0.busy, prompt: $0.prompt)) }
            // This poll takes about a second. Where the watch looked after it began,
            // the watch's answer is the newer one.
            for (id, at) in self.watchedAt where at > began {
                if let seen = self.parsed[id]?.state { next[id]?.state = seen }
            }
            for (id, p) in next { self.noteState(id, p.state) }
            self.parsed = next
            self.autoLabel()
            self.applyTints()
        }
    }

    /// The quick look at the flashing windows only: the full poll is too slow
    /// to stop a flash on time.
    private func watchFlashing() {
        guard !watching else { return }
        watching = true
        let began = CACurrentMediaTime()
        let ids = Array(haywireDirty)
        Backend.watch(ids) { [weak self] seen in
            guard let self else { return }
            self.watching = false
            // Failed, or a full poll that began later has already landed: drop it.
            guard let seen, began > self.pollBegan else { return }
            let now = CACurrentMediaTime()
            for id in ids {
                let state = seen[id].map { TerminalScript.state(title: $0.title, busy: self.info[id]?.busy ?? false, prompt: $0.prompt) } ?? .none
                let subtitle = seen[id].map { TerminalScript.subtitle(from: $0.title) } ?? self.parsed[id]?.subtitle ?? ""
                self.watchedAt[id] = now
                self.parsed[id] = (subtitle, state)
                self.noteState(id, state)
            }
        }
    }

    /// Stamps the moment a flashing window stopped waiting, for the log.
    private func noteState(_ id: Int, _ state: WorkState) {
        guard haywireDirty.contains(id) else { return }
        if state == .needsYou { clearedAt[id] = nil }
        else if clearedAt[id] == nil { clearedAt[id] = CACurrentMediaTime() }
    }

    /// The moment an agent window gets a real task title, it gets a label.
    private func autoLabel() {
        let store = Store.shared
        guard store.auto else { return }
        var procs: Procs?
        for (id, i) in info where store.group(forWindow: id) == nil && !store.isSkipped(id) {
            let st = parsed[id]?.state ?? .none
            guard st == .working || st == .yourTurn || st == .needsYou else { continue }
            if procs == nil { procs = Procs.all() }
            let cwd = i.tty.flatMap { procs?.cwd(tty: $0) }
            guard let pick = TerminalScript.autoName(title: i.title, cwd: cwd, groups: store.groups) else { continue }
            store.label(window: id, name: pick.name, color: nil, auto: true)
            // A second "Placard ..." window turns "Placard Background" into "Placard".
            if let g = pick.shorten, let word = g.name.split(separator: " ").first.map(String.init),
               let current = store.groups.first(where: { $0.id == g.id }) {
                store.rename(current, to: word, color: current.color)
                Log.write("auto-group \(g.name) renamed to \(word)")
            }
            Log.write("auto-labeled \(id) as \(pick.name)" + (cwd.map { " (cwd \($0))" } ?? ""))
        }
    }

    func applyTints() {
        let store = Store.shared
        for id in store.labeledWindows {
            guard let g = store.group(forWindow: id), let current = info[id]?.bg else { continue }
            if !store.tint || store.hidden { restoreBackground(id); continue }
            // A reading taken during a flash, or before its restore landed, is a
            // flash color: never keep it as the original, never tint from it.
            if haywireDirty.contains(id) || pollBegan < (cleanSince[id] ?? 0) { continue }
            if store.original(for: id) == nil { store.setOriginal(current, for: id) }
            let want = Palette.tint(g.color, over: store.original(for: id) ?? current)
            // Terminal rounds colors on the way back; only write on a real change.
            let off = zip(current, want).map { abs($0 - $1) }.max() ?? .max
            if current.count != 3 || off > 600 { Backend.setBackground(id, want) }
        }
    }

    // MARK: Christmas mode: the window's background and text cycle colors.

    private var haywireRuns: [Int: FlashRun] = [:]   // the cycle running now, per window
    private var haywireDirty = Set<Int>()                        // windows whose colors are not their own
    private var watching = false
    private var pollBegan: CFTimeInterval = 0                    // when the poll behind `info` started
    private var watchedAt: [Int: CFTimeInterval] = [:]           // last watch answer per window
    private var clearedAt: [Int: CFTimeInterval] = [:]           // when a flashing window stopped waiting
    private var cleanSince: [Int: CFTimeInterval] = [:]          // when a window's restore landed

    private func wantsFlash(_ id: Int) -> Bool { Store.shared.flash && parsed[id]?.state == .needsYou }

    private func startHaywire(_ id: Int) {
        guard haywireRuns[id] == nil else { return }
        if haywireDirty.insert(id).inserted {
            Store.shared.setFlashing(id, true)
            Log.write("flash start \(id)")
        }
        clearedAt[id] = nil
        haywireRuns[id] = Backend.haywire(id) { [weak self] in
            guard let self else { return }
            self.haywireRuns[id] = nil
            if !self.wantsFlash(id) { self.endHaywire(id) }
        }
    }

    private func endHaywire(_ id: Int) {
        guard haywireDirty.remove(id) != nil else { return }
        let store = Store.shared
        store.setFlashing(id, false)
        cleanSince[id] = .infinity
        var bg = store.original(for: id)
        if let g = store.group(forWindow: id), store.tint, !store.hidden, let base = bg { bg = Palette.tint(g.color, over: base) }
        let cleared = clearedAt.removeValue(forKey: id)
        Backend.restoreColors(id, bg: bg) { [weak self] in
            let now = CACurrentMediaTime()
            self?.cleanSince[id] = now
            Log.write("flash stop \(id)" + (cleared.map { ", colors back \(Int((now - $0) * 1000)) ms after the prompt went" } ?? ""))
        }
    }

    func restoreAllHaywire() {
        for run in haywireRuns.values { run.cancel() }
        for id in haywireDirty { endHaywire(id) }
    }

    func restoreBackground(_ id: Int) {
        guard let orig = Store.shared.original(for: id) else { return }
        Backend.resetBackground(id, orig)
        Store.shared.setOriginal(nil, for: id)
    }

    func restoreAll() {
        for id in Store.shared.labeledWindows { restoreBackground(id) }
    }
}
