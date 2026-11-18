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
        case name(color: Int)                      // over a visible strip
        case handle(color: Int?, initial: String)  // labels hidden, or window not labeled
    }

    var kind: Kind = .handle(color: nil, initial: "") { didSet { if kind != oldValue { restyle() } } }
    var onPrimary: (() -> Void)?
    var onMenu: (() -> Void)?
    private var hovering = false { didSet { restyle() } }
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
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch kind {
        case .name: p.x > bounds.width - 24 ? onMenu?() : onPrimary?()
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
        case .name(let c):
            layer?.contents = nil
            layer?.cornerRadius = 7
            let dark = Palette.all[c].darkText
            layer?.backgroundColor = hovering ? (dark ? NSColor(white: 0, alpha: 0.12) : NSColor(white: 1, alpha: 0.16)).cgColor : NSColor.clear.cgColor
            plus.isHidden = true
            letter.isHidden = true
        case .handle(let c, let initial):
            layer?.cornerRadius = 6
            if let c {
                layer?.contents = Dither.swatch(size: b.size, color: c)
                layer?.backgroundColor = nil
                layer?.opacity = hovering ? 1 : 0.92
                let isEmoji = initial.unicodeScalars.first.map { $0.properties.isEmoji && $0.value > 0x2000 } ?? false
                letter.string = NSAttributedString(string: initial, attributes: [
                    .font: isEmoji ? (NSFont(name: "AppleColorEmoji", size: 13) ?? .systemFont(ofSize: 13)) : Fonts.geist(12, "SemiBold"),
                    .foregroundColor: Palette.ink(c),
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
    private var timer: Timer?
    private var ticks = 0
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
        timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // With several displays this fires on every click into another display,
            // so never hide here: just rescan, the on-screen check does the rest.
            MainActor.assumeIsolated { self?.burst(0.6) }
        }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.burst(0.5) }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .keyDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.burst() }
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
        return list.compactMap { w in
            guard let id = w[kCGWindowNumber as String] as? Int,
                  let pid = w[kCGWindowOwnerPID as String] as? Int32,
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b),
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01
            else { return nil }
            return SceneWindow(id: id, pid: pid, layer: layer, frame: r)
        }
    }

    func tick() {
        let store = Store.shared
        ticks += 1
        if ticks % 75 == 0 { refreshInfo() }                // titles and status, every 1.25 s
        if ticks % 300 == 0, let alive = Windows.allTerminalIDs() { store.keepOnly(windows: alive) }

        guard let tpid = Windows.terminalApp?.processIdentifier else {
            if !slots.isEmpty { Log.write("slots cleared: Terminal not found"); slots.values.forEach { $0.strip.orderOut(nil); $0.control.orderOut(nil) }; slots.removeAll() }
            return
        }
        // Terminal windows = what Terminal's scripting reports (skips its Settings
        // window), plus anything labeled.
        let now = CACurrentMediaTime()
        // Full rate only around activity (clicks, keys, drags, moves, reorders);
        // otherwise 15 Hz is plenty and keeps the process near idle.
        if now > activeUntil && NSEvent.pressedMouseButtons == 0 && ticks % 4 != 0 { return }
        let known = Set(info.keys).union(store.labeledWindows)
        let raw = Windows.frames(for: Array(known))
        let moved = raw != lastRaw
        lastRaw = raw
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
        for (i, w) in scene_.enumerated() where w.pid == tpid && raw[w.id] != nil { index[w.id] = i }
        let hidden = store.hidden

        for (id, frame) in raw {
            let slot = slots[id] ?? {
                let s = Slot()
                s.control.control.onPrimary = { [weak self] in self?.primary(id) }
                s.control.control.onMenu = { [weak self] in self?.showMenu(id) }
                slots[id] = s
                return s
            }()
            if quiet { slot.strip.orderOut(nil); slot.control.orderOut(nil); continue }

            // Christmas mode while the agent waits on an approval, or briefly after it finishes.
            let wantHaywire = store.flash && (parsed[id]?.state == .needsYou || now < (celebrateUntil[id] ?? 0))
            if wantHaywire { startHaywire(id) }
            else if haywireDirty.contains(id) && !haywireRunning.contains(id) { endHaywire(id) }

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
                slot.strip.strip.configure(.init(name: g.name, emoji: store.emoji(forWindow: id) ?? "", subtitle: p?.subtitle ?? "", color: g.color, state: p?.state ?? .none))
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
            var controlCG: CGRect
            if showStrip, let g = group {
                slot.strip.strip.layoutSubtreeIfNeeded()
                let r = slot.strip.strip.controlRect
                controlCG = CGRect(x: stripCG.minX + r.minX, y: stripCG.minY + (stripCG.height - r.maxY), width: r.width, height: r.height)
                slot.control.control.kind = .name(color: g.color)
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

    private var celebrateUntil: [Int: CFTimeInterval] = [:]
    private var missing: [Int: Int] = [:]

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
        if Store.shared.group(forWindow: id) != nil { actions?.renameGroup(of: id, anchor: anchor(id)) }
        else { actions?.labelWindow(id, anchor: anchor(id)) }
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

    func state(for id: Int) -> (subtitle: String, state: WorkState) { parsed[id] ?? ("", .none) }

    func refreshInfo() {
        guard !polling, Windows.terminalApp != nil else { return }
        polling = true
        TerminalScript.titles { [weak self] map in
            guard let self else { return }
            self.polling = false
            let before = self.parsed
            self.info = map
            self.parsed = map.mapValues { (TerminalScript.subtitle(from: $0.title), TerminalScript.state(title: $0.title, busy: $0.busy, prompt: $0.prompt)) }
            let now = CACurrentMediaTime()
            for (id, p) in self.parsed where before[id]?.state == .working && p.state == .yourTurn {
                self.celebrateUntil[id] = now + 5
                self.burst(5.5)
            }
            self.autoLabel()
            self.applyTints()
        }
    }

    /// The moment an agent window gets a real task title, it gets a label.
    private func autoLabel() {
        let store = Store.shared
        guard store.auto else { return }
        for (id, i) in info where store.group(forWindow: id) == nil && !store.isSkipped(id) {
            let st = parsed[id]?.state ?? .none
            guard st == .working || st == .yourTurn || st == .needsYou,
                  let name = TerminalScript.autoName(title: i.title, groups: store.groups) else { continue }
            store.label(window: id, name: name, color: nil)
            Log.write("auto-labeled \(id) as \(name)")
        }
    }

    func applyTints() {
        let store = Store.shared
        for id in store.labeledWindows {
            guard let g = store.group(forWindow: id), let current = info[id]?.bg else { continue }
            if !store.tint || store.hidden { restoreBackground(id); continue }
            if store.original(for: id) == nil { store.setOriginal(current, for: id) }
            if haywireDirty.contains(id) { continue }
            let want = Palette.tint(g.color, over: store.original(for: id) ?? current)
            // Terminal rounds colors on the way back; only write on a real change.
            let off = zip(current, want).map { abs($0 - $1) }.max() ?? .max
            if current.count != 3 || off > 600 { TerminalScript.setBackground(id, want) }
        }
    }

    // MARK: Christmas mode: the window's background and text cycle colors.

    private var haywireRunning = Set<Int>()
    private var haywireDirty = Set<Int>()

    private func startHaywire(_ id: Int) {
        guard !haywireRunning.contains(id), let i = info[id] else { return }
        let store = Store.shared
        if store.originalColors(for: id) == nil {
            let bg = store.original(for: id) ?? i.bg
            store.setOriginalColors(bg + i.fg + i.bold, for: id)
        }
        haywireRunning.insert(id)
        haywireDirty.insert(id)
        TerminalScript.haywire(id) { [weak self] in self?.haywireRunning.remove(id) }
    }

    private func endHaywire(_ id: Int) {
        haywireDirty.remove(id)
        let store = Store.shared
        guard let o = store.originalColors(for: id), o.count == 9 else { return }
        var bg = Array(o[0..<3])
        if let g = store.group(forWindow: id), store.tint, !store.hidden {
            if store.original(for: id) == nil { store.setOriginal(bg, for: id) }
            bg = Palette.tint(g.color, over: bg)
        }
        TerminalScript.setColors(id, bg: bg, fg: Array(o[3..<6]), bold: Array(o[6..<9]))
        store.setOriginalColors(nil, for: id)
    }

    func restoreAllHaywire() { for id in haywireDirty { endHaywire(id) } }

    func restoreBackground(_ id: Int) {
        guard let orig = Store.shared.original(for: id) else { return }
        TerminalScript.setBackground(id, orig)
        Store.shared.setOriginal(nil, for: id)
    }

    func restoreAll() {
        for id in Store.shared.labeledWindows { restoreBackground(id) }
    }
}
