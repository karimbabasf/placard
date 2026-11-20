import AppKit
import QuartzCore

/// Small floating panel that names a window, renames a group, or retitles a window's task.
@MainActor
final class PromptController: NSObject, NSTextFieldDelegate {
    enum Mode { case label(window: Int, frame: CGRect), rename(Group, frame: CGRect), task(window: Int, frame: CGRect) }

    private var panel: PromptPanel?
    private var mode: Mode = .label(window: 0, frame: .zero)
    private var color = 0
    private var colorTouched = false
    private let field = NSTextField()
    private var swatches: [SwatchView] = []
    private var chips: [ChipView] = []
    private var onDone: (() -> Void)?

    private let width: CGFloat = 460
    private let pad: CGFloat = 12
    private let radius: CGFloat = 22

    func show(_ mode: Mode, onDone: @escaping () -> Void) {
        close(restoreFocus: false)
        self.mode = mode
        self.onDone = onDone
        let store = Store.shared
        var initialName = ""
        switch mode {
        case .label(let id, _):
            if let g = store.group(forWindow: id) { initialName = g.name; color = g.color } else { color = store.nextFreeColor() }
        case .rename(let g, _):
            initialName = g.name; color = g.color
        case .task(let id, _):
            initialName = store.task(forWindow: id) ?? taskProvider?(id) ?? ""
            color = store.group(forWindow: id)?.color ?? 0
        }
        colorTouched = false
        build(initialName: initialName)
    }

    private var others: [Group] {
        let all = Store.shared.groups
        if case .rename(let g, _) = mode { return all.filter { $0.id != g.id } }
        if case .task = mode { return [] }
        return all
    }

    private func build(initialName: String) {
        let inner = width - pad * 2
        let fieldH: CGFloat = 56
        let chipH: CGFloat = 32
        let swatchS: CGFloat = 28
        let hasChips = !others.isEmpty
        var isTask = false
        if case .task = mode { isTask = true }
        let height = pad + StripMetrics.height + 10 + fieldH + 14 + (hasChips ? chipH + 12 : 0) + (isTask ? 0 : swatchS + 16) + 18 + pad + 4

        let p = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height))
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.material = .hudWindow
        root.state = .active
        root.blendingMode = .behindWindow
        root.wantsLayer = true
        root.layer?.cornerRadius = radius
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        p.contentView = root
        p.appearance = NSAppearance(named: .darkAqua)

        var y = height - pad - StripMetrics.height
        let pv = StripView(frame: NSRect(x: pad, y: y, width: inner, height: StripMetrics.height))
        root.addSubview(pv)
        preview = pv
        y -= 10 + fieldH

        // Name field on a raised surface step, concentric with the panel corner.
        let well = NSView(frame: NSRect(x: pad, y: y, width: inner, height: fieldH))
        well.wantsLayer = true
        well.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        well.layer?.cornerRadius = radius - pad
        well.layer?.cornerCurve = .continuous
        root.addSubview(well)

        // Size the field from the font's real line height, or big type clips at the top.
        let fieldFont = Fonts.geist(24, "SemiBold")
        let lineH = ceil(fieldFont.ascender - fieldFont.descender + fieldFont.leading) + 4
        field.frame = NSRect(x: 16, y: (fieldH - lineH) / 2, width: inner - 32, height: lineH)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = fieldFont
        field.textColor = .white
        field.stringValue = initialName
        field.placeholderAttributedString = NSAttributedString(string: isTask ? "What is this agent on?" : "Name this window", attributes: [
            .font: fieldFont, .foregroundColor: NSColor(white: 1, alpha: 0.42),
        ])
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        well.addSubview(field)

        y -= 14

        chips = []
        if hasChips {
            y -= chipH
            var x = pad
            for (i, g) in others.enumerated() {
                let c = ChipView(group: g, number: i < 9 ? i + 1 : nil)
                let w = c.fittingWidth
                if x + w > pad + inner { break }
                c.frame = NSRect(x: x, y: y, width: w, height: chipH)
                c.onClick = { [weak self] in self?.pick(group: g) }
                root.addSubview(c)
                chips.append(c)
                x += w + 8
            }
            y -= 12
        }

        swatches = []
        if !isTask { y -= swatchS + 16 }
        for i in 0..<(isTask ? 0 : Palette.all.count) {
            let s = SwatchView(index: i, size: swatchS, radius: 8, selectable: true)
            s.frame.origin = NSPoint(x: pad + CGFloat(i) * (swatchS + 10), y: y + 16)
            s.onClick = { [weak self] in self?.setColor(i, touched: true) }
            root.addSubview(s)
            swatches.append(s)
        }

        y -= 18
        let hint = NSTextField(labelWithString: isTask ? "Return to save   Empty uses the Terminal title   Esc to close"
                                                       : "Return to label   Tab to change color   Esc to close")
        hint.font = Fonts.geist(12, "Medium")
        hint.textColor = NSColor(white: 1, alpha: 0.55)
        hint.frame = NSRect(x: pad + 2, y: y, width: inner - 120, height: 18)
        root.addSubview(hint)

        if case .label(let id, _) = mode, Store.shared.group(forWindow: id) != nil {
            let remove = LinkButton(title: "Remove label") { [weak self] in self?.removeLabel() }
            remove.frame = NSRect(x: pad + inner - 110, y: y - 2, width: 110, height: 22)
            root.addSubview(remove)
        }

        setColor(color, touched: false)
        updateMatch()

        // Center over the target window, clamped to its screen.
        var anchor = NSScreen.main?.visibleFrame ?? .zero
        switch mode {
        case .label(_, let f), .rename(_, let f), .task(_, let f): if f != .zero { anchor = Windows.cocoaRect(f) }
        }
        var origin = NSPoint(x: anchor.midX - width / 2, y: anchor.midY - height / 2 + anchor.height * 0.12)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 12), vf.maxX - width - 12)
            origin.y = min(max(origin.y, vf.minY + 12), vf.maxY - height - 12)
        }
        p.setFrameOrigin(origin)

        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)

        root.layer?.transform = CATransform3DMakeScale(0.97, 0.97, 1)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            p.animator().alphaValue = 1
        }
        let s = CABasicAnimation(keyPath: "transform.scale")
        s.fromValue = 0.97
        s.toValue = 1
        s.duration = 0.22
        s.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        root.layer?.add(s, forKey: "in")
        root.layer?.transform = CATransform3DIdentity
    }

    private weak var preview: StripView?
    var stateProvider: ((Int) -> (subtitle: String, state: WorkState))?
    var taskProvider: ((Int) -> String)?

    private func updatePreview() {
        var sub = "", st = WorkState.none
        var emoji = ""
        if case .label(let id, _) = mode, let p = stateProvider?(id) { sub = p.subtitle; st = p.state; emoji = Store.shared.emoji(forWindow: id) ?? "" }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        if case .task(let id, _) = mode {
            let p = stateProvider?(id)
            preview?.configure(.init(name: Store.shared.group(forWindow: id)?.name ?? "", emoji: Store.shared.emoji(forWindow: id) ?? "",
                                     subtitle: name.isEmpty ? (taskProvider?(id) ?? "") : name, color: color, state: p?.state ?? .none))
            return
        }
        preview?.configure(.init(name: name.isEmpty ? "Untitled" : name, emoji: emoji, subtitle: sub, color: color, state: st))
    }

    private func setColor(_ i: Int, touched: Bool) {
        color = (i + Palette.all.count) % Palette.all.count
        if touched { colorTouched = true }
        for s in swatches { s.selected = s.index == color }
        updatePreview()
    }

    private func pick(group g: Group) {
        field.stringValue = g.name
        field.currentEditor()?.moveToEndOfDocument(nil)
        setColor(g.color, touched: false)
        updateMatch()
    }

    private func updateMatch() {
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        let match = others.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        for c in chips { c.highlighted = c.group.id == match?.id }
        if !colorTouched {
            if let m = match { setColor(m.color, touched: false) }
            else if case .label = mode, !name.isEmpty { setColor(Store.shared.nextFreeColor(), touched: false) }
        }
        updatePreview()
    }

    func controlTextDidChange(_ obj: Notification) { updateMatch() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)): submit(); return true
        case #selector(NSResponder.cancelOperation(_:)): close(restoreFocus: true); return true
        case #selector(NSResponder.insertTab(_:)): if case .task = mode { return true }; setColor(color + 1, touched: true); return true
        case #selector(NSResponder.insertBacktab(_:)): if case .task = mode { return true }; setColor(color - 1, touched: true); return true
        default: return false
        }
    }

    private func submit() {
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .task(let id, _) = mode {
            // typing the Terminal title back in, or nothing, clears the override
            Store.shared.setTask(name == taskProvider?(id) ? "" : name, forWindow: id)
            close(restoreFocus: true)
            return
        }
        guard !name.isEmpty else { shake(); return }
        switch mode {
        case .label(let id, _): Store.shared.label(window: id, name: String(name.prefix(40)), color: color, pinned: colorTouched)
        case .rename(let g, _): Store.shared.rename(g, to: String(name.prefix(40)), color: color, pinned: colorTouched)
        case .task: break
        }
        close(restoreFocus: true)
    }

    private func removeLabel() {
        if case .label(let id, _) = mode { Store.shared.unlabel(window: id) }
        close(restoreFocus: true)
    }

    private func shake() {
        guard let p = panel else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [0, -8, 7, -5, 3, 0]
        a.duration = 0.3
        p.contentView?.layer?.add(a, forKey: "shake")
    }

    func close(restoreFocus: Bool) {
        guard let p = panel else { return }
        panel = nil
        p.orderOut(nil)
        if restoreFocus { Windows.activateFront() }
        onDone?()
    }
}

final class PromptPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .modalPanel
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    }
    override var canBecomeKey: Bool { true }
}

final class SwatchView: NSView {
    var index: Int { didSet { redraw() } }
    var selected = false { didSet { redraw() } }
    var onClick: (() -> Void)?
    private let selectable: Bool
    private let check = CAShapeLayer()

    init(index: Int, size: CGFloat, radius: CGFloat, selectable: Bool) {
        self.index = index
        self.selectable = selectable
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        let path = CGMutablePath()
        let s = size
        path.move(to: CGPoint(x: s * 0.28, y: s * 0.52))
        path.addLine(to: CGPoint(x: s * 0.44, y: s * 0.36))
        path.addLine(to: CGPoint(x: s * 0.73, y: s * 0.66))
        check.path = path
        check.fillColor = nil
        check.lineWidth = 2.4
        check.lineCap = .round
        check.lineJoin = .round
        layer?.addSublayer(check)
        redraw()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func redraw() {
        if bounds.width < 16 {
            // Too small for a dither to read: plain fill.
            layer?.contents = nil
            layer?.backgroundColor = Palette.fill(index).cgColor
            check.isHidden = true
            return
        }
        layer?.contents = Dither.swatch(size: bounds.size, color: index)
        layer?.magnificationFilter = .nearest
        layer?.masksToBounds = true
        check.strokeColor = Palette.ink(index).cgColor
        check.isHidden = !(selectable && selected)
    }

    override func mouseDown(with event: NSEvent) { if selectable { onClick?() } }
    override func resetCursorRects() { if selectable { addCursorRect(bounds, cursor: .pointingHand) } }
}

final class ChipView: NSView {
    let group: Group
    var onClick: (() -> Void)?
    var highlighted = false { didSet { layer?.backgroundColor = bg.cgColor } }
    private let label: NSTextField
    private let dot: SwatchView
    private var hovering = false { didSet { layer?.backgroundColor = bg.cgColor } }

    private var bg: NSColor {
        if highlighted { return Palette.fill(group.color).withAlphaComponent(0.32) }
        return NSColor(white: 1, alpha: hovering ? 0.14 : 0.08)
    }

    init(group: Group, number: Int?) {
        self.group = group
        label = NSTextField(labelWithString: group.name)
        dot = SwatchView(index: group.color, size: 10, radius: 3, selectable: false)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = bg.cgColor
        label.font = Fonts.geist(14, "Medium")
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        addSubview(dot)
        addSubview(label)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    var fittingWidth: CGFloat {
        let w = ceil((group.name as NSString).size(withAttributes: [.font: Fonts.geist(14, "Medium")]).width)
        return min(200, 30 + w + 14)
    }

    override func layout() {
        super.layout()
        dot.frame.origin = NSPoint(x: 12, y: (bounds.height - 10) / 2)
        let h = label.intrinsicContentSize.height
        label.frame = NSRect(x: 30, y: (bounds.height - h) / 2, width: bounds.width - 30 - 8, height: h)
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

final class LinkButton: NSButton {
    private let action_: () -> Void
    init(title: String, action: @escaping () -> Void) {
        action_ = action
        super.init(frame: .zero)
        isBordered = false
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Fonts.geist(12.5, "Medium"),
            .foregroundColor: NSColor(srgbRed: 1, green: 0.62, blue: 0.6, alpha: 1),
        ])
        alignment = .right
        target = self
        self.action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { action_() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
