import AppKit
import Carbon
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, WindowActions {
    private var statusItem: NSStatusItem!
    private let overlays = OverlayManager()
    private let prompt = PromptController()

    func applicationDidFinishLaunching(_ note: Notification) {
        Fonts.register()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let img = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: "Placard")
        img?.isTemplate = true
        statusItem.button?.image = img
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        Store.shared.onChange = { [weak self] in self?.overlays.refreshInfo() }
        prompt.stateProvider = { [weak self] id in self?.overlays.state(for: id) ?? ("", .none) }
        overlays.actions = self
        overlays.start()

        let keys = Hotkeys.shared
        keys.register(key: kVK_ANSI_L) { [weak self] in self?.labelFrontWindow() }
        keys.register(key: kVK_ANSI_U) { [weak self] in self?.unlabelFrontWindow() }
        keys.register(key: kVK_ANSI_T) { [weak self] in self?.tileFrontGroup() }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (i, k) in digits.enumerated() {
            keys.register(key: k) { [weak self] in self?.raiseGroup(at: i) }
        }

        requestAutomation()

        if !Store.shared.saved.didFirstLaunch {
            try? SMAppService.mainApp.register()
            Store.shared.markFirstLaunchDone()
        }
    }

    /// Asks for "control Terminal" up front, in-process, so the consent dialog
    /// is attributed to Placard and actually shows.
    func requestAutomation() {
        guard Windows.terminalApp != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        let target = NSAppleEventDescriptor(bundleIdentifier: Windows.bundleID)
        DispatchQueue.global(qos: .userInitiated).async {
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
            Log.write("automation permission status \(status)")
            DispatchQueue.main.async { MainActor.assumeIsolated { self.overlays.refreshInfo() } }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlays.restoreAllHaywire()
        overlays.restoreAll()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    // MARK: actions

    func labelFrontWindow() {
        guard let w = Windows.frontTerminalWindow() else { NSSound.beep(); return }
        prompt.show(.label(window: w.id, frame: w.frame)) {}
    }

    func unlabelFrontWindow() {
        guard let w = Windows.frontTerminalWindow() else { return }
        Store.shared.unlabel(window: w.id)
    }

    func raiseGroup(at index: Int) {
        let groups = Store.shared.groups
        guard index < groups.count else { NSSound.beep(); return }
        TerminalScript.raise(Store.shared.windows(in: groups[index]))
    }

    func tileFrontGroup() {
        guard let w = Windows.frontTerminalWindow(), let g = Store.shared.group(forWindow: w.id) else { NSSound.beep(); return }
        tile(g)
    }

    func tile(_ g: Group) {
        let ids = Store.shared.windows(in: g)
        guard !ids.isEmpty else { return }
        let frames = Dictionary(Windows.snapshot().terminal.map { ($0.id, $0.frame) }, uniquingKeysWith: { a, _ in a })
        let anchor = ids.compactMap { frames[$0] }.first.map(Windows.cocoaRect)
        let screen = NSScreen.screens.first { anchor.map($0.frame.intersects) ?? false } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        let area = Windows.cgRect(vf).insetBy(dx: 8, dy: 8)
        let n = ids.count
        let rows = n <= 3 ? 1 : 2
        let cols = Int(ceil(Double(n) / Double(rows)))
        let gap: CGFloat = 8
        let cw = (area.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let ch = (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        var items: [(Int, CGRect)] = []
        for (i, id) in ids.enumerated() {
            let r = i / cols, c = i % cols
            items.append((id, CGRect(x: area.minX + CGFloat(c) * (cw + gap), y: area.minY + CGFloat(r) * (ch + gap), width: cw, height: ch)))
        }
        TerminalScript.setBounds(items)
    }

    /// placard://label?name=API&tty=/dev/ttys003   (or &window=12345)
    /// placard://unlabel?tty=/dev/ttys003
    /// placard://raise?name=API     placard://tile?name=API
    func handle(_ url: URL) {
        guard url.scheme == "placard" else { return }
        let q = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                           uniquingKeysWith: { a, _ in a })
        let action = url.host ?? ""
        let name = q["name"] ?? ""
        let color = q["color"].flatMap { c in Int(c) ?? Palette.all.firstIndex { $0.name.lowercased() == c.lowercased() } }

        func withWindow(_ body: @escaping (Int) -> Void) {
            if let w = q["window"].flatMap(Int.init) { body(w) }
            else if let tty = q["tty"], !tty.isEmpty { TerminalScript.window(forTTY: tty) { if let id = $0 { body(id) } } }
            else if let w = Windows.frontTerminalWindow() { body(w.id) }
        }

        switch action {
        case "label" where !name.isEmpty: withWindow { Store.shared.label(window: $0, name: name, color: color) }
        case "label": withWindow { id in
            let f = Windows.snapshot().terminal.first { $0.id == id }?.frame ?? .zero
            self.prompt.show(.label(window: id, frame: f)) {}
        }
        case "unlabel": withWindow { Store.shared.unlabel(window: $0) }
        case "raise": if let g = Store.shared.group(named: name) { TerminalScript.raise(Store.shared.windows(in: g)) }
        case "tile": if let g = Store.shared.group(named: name) { tile(g) }
        default: break
        }
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let front = Windows.frontTerminalWindow()
        let label = NSMenuItem(title: front.flatMap { Store.shared.group(forWindow: $0.id) } == nil ? "Label Front Window\u{2026}" : "Relabel Front Window\u{2026}",
                               action: #selector(menuLabel), keyEquivalent: "l")
        label.keyEquivalentModifierMask = [.control, .option]
        label.target = self
        label.isEnabled = front != nil
        menu.addItem(label)
        menu.addItem(.separator())

        let groups = Store.shared.groups
        if groups.isEmpty {
            let empty = NSMenuItem(title: "No labels yet. Press \u{2303}\u{2325}L in a Terminal window.", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (i, g) in groups.enumerated() {
            let count = Store.shared.windows(in: g).count
            let item = NSMenuItem(title: "\(g.name)", action: #selector(menuRaise(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            item.keyEquivalentModifierMask = [.control, .option]
            item.target = self
            item.representedObject = g.id
            item.image = Self.dot(g.color)
            item.badge = NSMenuItemBadge(count: count)

            let sub = NSMenu()
            func add(_ title: String, _ sel: Selector) {
                let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
                it.target = self
                it.representedObject = g.id
                sub.addItem(it)
            }
            add("Bring to Front", #selector(menuRaise(_:)))
            add("Tile on One Screen", #selector(menuTile(_:)))
            add("Rename\u{2026}", #selector(menuRename(_:)))
            let colors = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
            let cm = NSMenu()
            for (ci, s) in Palette.all.enumerated() {
                let it = NSMenuItem(title: s.name, action: #selector(menuColor(_:)), keyEquivalent: "")
                it.target = self
                it.image = Self.dot(ci)
                it.state = ci == g.color ? .on : .off
                it.representedObject = [g.id.uuidString, String(ci)]
                cm.addItem(it)
            }
            colors.submenu = cm
            sub.addItem(colors)
            sub.addItem(.separator())
            add("Remove Label from \(count == 1 ? "Window" : "All \(count) Windows")", #selector(menuDissolve(_:)))
            item.submenu = sub
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Show Labels", action: #selector(menuHidden), keyEquivalent: "")
        hide.target = self
        hide.state = Store.shared.hidden ? .off : .on
        menu.addItem(hide)
        let tint = NSMenuItem(title: "Tint Window Background", action: #selector(menuTint), keyEquivalent: "")
        tint.target = self
        tint.state = Store.shared.tint ? .on : .off
        menu.addItem(tint)
        menu.addItem(item("Auto-Label Agent Windows", state: Store.shared.auto) { Store.shared.auto.toggle() })
        menu.addItem(item("Flash When an Agent Needs You", state: Store.shared.flash) { Store.shared.flash.toggle() })
        let login = NSMenuItem(title: "Open at Login", action: #selector(menuLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Placard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func group(_ sender: NSMenuItem) -> Group? {
        guard let id = sender.representedObject as? UUID else { return nil }
        return Store.shared.groups.first { $0.id == id }
    }

    @objc private func menuLabel() { DispatchQueue.main.async { self.labelFrontWindow() } }
    @objc private func menuRaise(_ s: NSMenuItem) { if let g = group(s) { TerminalScript.raise(Store.shared.windows(in: g)) } }
    @objc private func menuTile(_ s: NSMenuItem) { if let g = group(s) { tile(g) } }
    @objc private func menuDissolve(_ s: NSMenuItem) { if let g = group(s) { Store.shared.dissolve(g) } }
    @objc private func menuRename(_ s: NSMenuItem) {
        guard let g = group(s) else { return }
        DispatchQueue.main.async { self.prompt.show(.rename(g, frame: .zero)) {} }
    }
    @objc private func menuColor(_ s: NSMenuItem) {
        guard let pair = s.representedObject as? [String], pair.count == 2,
              let g = Store.shared.groups.first(where: { $0.id.uuidString == pair[0] }), let c = Int(pair[1]) else { return }
        Store.shared.setColor(g, c)
    }
    @objc private func menuHidden() {
        Store.shared.hidden.toggle()
        if Store.shared.hidden { overlays.restoreAll() } else { overlays.applyTints() }
    }
    @objc private func menuTint() {
        Store.shared.tint.toggle()
        if !Store.shared.tint { overlays.restoreAll() }
    }
    @objc private func menuLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() } else { try? SMAppService.mainApp.register() }
    }

    // MARK: per-window dropdown

    func renameGroup(of window: Int, anchor: CGRect) {
        guard let g = Store.shared.group(forWindow: window) else { return }
        prompt.show(.rename(g, frame: anchor)) {}
    }

    func labelWindow(_ window: Int, anchor: CGRect) {
        prompt.show(.label(window: window, frame: anchor)) {}
    }

    private final class Box: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }
    @objc private func runBox(_ s: NSMenuItem) { (s.representedObject as? Box)?.run() }

    private func item(_ title: String, key: String = "", image: NSImage? = nil, state: Bool = false, _ run: @escaping () -> Void) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: #selector(runBox(_:)), keyEquivalent: key)
        if !key.isEmpty { it.keyEquivalentModifierMask = [.control, .option] }
        it.target = self
        it.representedObject = Box(run)
        it.image = image
        it.state = state ? .on : .off
        return it
    }

    func windowMenu(for window: Int, anchor: CGRect) -> NSMenu {
        let store = Store.shared
        let menu = NSMenu()
        menu.autoenablesItems = false
        let groups = store.groups
        if let g = store.group(forWindow: window) {
            let n = store.windows(in: g).count
            let head = NSMenuItem(title: "\(store.emoji(forWindow: window) ?? "") \(g.name)  \u{00B7}  \(n) window\(n == 1 ? "" : "s")", action: nil, keyEquivalent: "")
            head.isEnabled = false
            head.image = Self.dot(g.color)
            menu.addItem(head)
            menu.addItem(.separator())
            menu.addItem(item("Rename Group\u{2026}") { [weak self] in self?.renameGroup(of: window, anchor: anchor) })
            let colors = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
            let cm = NSMenu()
            for (ci, s) in Palette.all.enumerated() {
                cm.addItem(item(s.name, image: Self.dot(ci), state: ci == g.color) { Store.shared.setColor(g, ci) })
            }
            colors.submenu = cm
            menu.addItem(colors)
            menu.addItem(item("New Emoji") { Store.shared.shuffleEmoji(window) })
            menu.addItem(.separator())
            let idx = groups.firstIndex { $0.id == g.id } ?? 99
            menu.addItem(item("Bring Group to Front", key: idx < 9 ? "\(idx + 1)" : "") { TerminalScript.raise(Store.shared.windows(in: g)) })
            menu.addItem(item("Tile Group", key: "t") { [weak self] in self?.tile(g) })
            let others = groups.filter { $0.id != g.id }
            let move = NSMenuItem(title: "Move Window To", action: nil, keyEquivalent: "")
            let mm = NSMenu()
            for o in others { mm.addItem(item(o.name, image: Self.dot(o.color)) { Store.shared.label(window: window, name: o.name, color: nil) }) }
            if !others.isEmpty { mm.addItem(.separator()) }
            mm.addItem(item("New Group\u{2026}") { [weak self] in
                Store.shared.unlabel(window: window)
                self?.labelWindow(window, anchor: anchor)
            })
            move.submenu = mm
            menu.addItem(move)
            menu.addItem(.separator())
            menu.addItem(item("Remove Label", key: "u") { Store.shared.unlabel(window: window) })
        } else {
            menu.addItem(item("Label This Window\u{2026}", key: "l") { [weak self] in self?.labelWindow(window, anchor: anchor) })
            if !groups.isEmpty {
                let add = NSMenuItem(title: "Add to Group", action: nil, keyEquivalent: "")
                let am = NSMenu()
                for o in groups { am.addItem(item(o.name, image: Self.dot(o.color)) { Store.shared.label(window: window, name: o.name, color: nil) }) }
                add.submenu = am
                menu.addItem(add)
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("Show Labels", state: !store.hidden) { [weak self] in self?.menuHidden() })
        menu.addItem(item("Tint Window Background", state: store.tint) { [weak self] in self?.menuTint() })
        menu.addItem(item("Auto-Label Agent Windows", state: store.auto) { Store.shared.auto.toggle() })
        menu.addItem(item("Flash When an Agent Needs You", state: store.flash) { Store.shared.flash.toggle() })
        return menu
    }

    static func dot(_ color: Int) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            let box = r.insetBy(dx: 1, dy: 1)
            NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).addClip()
            if let img = Dither.swatch(size: box.size, color: color), let ctx = NSGraphicsContext.current?.cgContext {
                ctx.interpolationQuality = .none
                ctx.draw(img, in: box)
            }
            return true
        }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
