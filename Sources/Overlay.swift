import AppKit
import QuartzCore

enum Fonts {
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for f in files where ["ttf", "otf", "woff2"].contains(f.pathExtension) {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
        }
    }

    static func geist(_ size: CGFloat, _ weight: String) -> NSFont {
        NSFont(name: "Geist-\(weight)", size: size) ?? .systemFont(ofSize: size, weight: weight == "SemiBold" ? .semibold : .medium)
    }

    static func pixel(_ size: CGFloat) -> NSFont {
        NSFont(name: "GeistPixel-Square", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .medium)
    }
}

/// The strip lives inside Terminal's 32 pt title bar, right of the traffic lights.
enum StripMetrics {
    static let titleBar: CGFloat = 32
    static let left: CGFloat = 76          // clears the traffic lights
    static let inset: CGFloat = 3
    static let windowRadius: CGFloat = 16
    static var height: CGFloat { titleBar - inset * 2 }
    static var outerRadius: CGFloat { windowRadius - inset }   // concentric with the window corner
    static let innerRadius: CGFloat = 7
    static let fade: CGFloat = 14          // text inset from the strip's left edge

    static func frame(for window: CGRect) -> CGRect {
        CGRect(x: window.minX + left, y: window.minY + inset,
               width: max(60, window.width - left - inset), height: height)
    }

    /// Concentric top-right (next to the window corner), tighter elsewhere.
    static func shape(_ size: CGSize) -> CGPath {
        let w = size.width, h = size.height
        let tr = min(outerRadius, h / 2), br = min(innerRadius, h / 2)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: br, y: 0))
        p.addLine(to: CGPoint(x: w - br, y: 0))
        p.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: br), radius: br)
        p.addLine(to: CGPoint(x: w, y: h - tr))
        p.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - tr, y: h), radius: tr)
        p.addLine(to: CGPoint(x: br, y: h))
        p.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - br), radius: br)
        p.addLine(to: CGPoint(x: 0, y: br))
        p.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: br, y: 0), radius: br)
        p.closeSubpath()
        return p
    }
}

final class StripPanel: NSPanel {
    let strip = StripView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: StripMetrics.height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // Above normal windows so a click on Terminal never covers the strip;
        // occlusion by windows in front is handled with a mask instead.
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary, .transient]
        contentView = strip
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class StripView: NSView {
    struct Model: Equatable {
        var name = ""
        var emoji = ""
        var subtitle = ""
        var color = 0
        var state: WorkState = .none
    }

    private(set) var model = Model()
    private var configured = false
    private let body = CALayer()          // clipped by `shape`
    private let shape = CAShapeLayer()
    private let fill = CALayer()
    private let shimmer = CALayer()
    private let nameLayer = CATextLayer()
    private let emojiLayer = CALayer()
    private let subLayer = CATextLayer()
    private let statusLayer = CATextLayer()
    private var dots: [CALayer] = []
    private let chevron = CAShapeLayer()
    /// The clickable name area, in local points (the control panel sits here).
    private(set) var controlRect: CGRect = .zero
    private var fillKey = ""
    private var occluders: [CGRect] = []
    private var shimmerWidth: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        body.mask = shape
        layer?.addSublayer(body)
        fill.magnificationFilter = .nearest
        fill.contentsGravity = .resize
        body.addSublayer(fill)
        shimmer.magnificationFilter = .nearest
        shimmer.contentsGravity = .resize
        shimmer.isHidden = true
        body.addSublayer(shimmer)
        emojiLayer.contentsGravity = .resizeAspect
        body.addSublayer(emojiLayer)
        for t in [nameLayer, subLayer, statusLayer] {
            t.contentsScale = 2
            t.truncationMode = .end
            t.isWrapped = false
            body.addSublayer(t)
        }
        nameLayer.font = Fonts.geist(17, "SemiBold")
        nameLayer.fontSize = 17
        subLayer.font = Fonts.geist(12.5, "Medium")
        subLayer.fontSize = 12.5
        statusLayer.font = Fonts.pixel(12)
        statusLayer.fontSize = 12
        statusLayer.alignmentMode = .right
        let cp = CGMutablePath()
        cp.move(to: CGPoint(x: 0.5, y: 5.5))
        cp.addLine(to: CGPoint(x: 4.5, y: 1.5))
        cp.addLine(to: CGPoint(x: 8.5, y: 5.5))
        chevron.path = cp
        chevron.fillColor = nil
        chevron.lineWidth = 1.8
        chevron.lineCap = .round
        chevron.lineJoin = .round
        body.addSublayer(chevron)
        for _ in 0..<4 {
            let d = CALayer()
            d.magnificationFilter = .nearest
            body.addSublayer(d)
            dots.append(d)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = window?.backingScaleFactor ?? 2
        for t in [nameLayer, subLayer, statusLayer] { t.contentsScale = s }
    }

    func configure(_ m: Model) {
        guard m != model || !configured else { return }
        let old = model
        model = m
        configured = true
        let ink = Palette.ink(m.color, dull: m.state != .working && m.state != .needsYou)
        CATransaction.begin()
        CATransaction.setDisableActions(old.color == m.color)
        nameLayer.foregroundColor = ink.cgColor
        subLayer.foregroundColor = ink.withAlphaComponent(0.84).cgColor
        statusLayer.foregroundColor = ink.withAlphaComponent(0.92).cgColor
        for d in dots { d.backgroundColor = ink.cgColor }
        chevron.strokeColor = ink.withAlphaComponent(0.7).cgColor
        nameLayer.string = m.name
        if m.emoji != old.emoji || emojiLayer.contents == nil { emojiLayer.contents = Self.emojiImage(m.emoji) }
        subLayer.string = m.subtitle
        statusLayer.string = Self.statusText(m.state)
        CATransaction.commit()
        if old.state != m.state { applyState() }
        if old.color != m.color { fillKey = "" }
        needsLayout = true
    }

    /// Emoji as a bitmap fitted from its real ink bounds, so no part of the glyph
    /// can fall outside a text line box and get clipped.
    static func emojiImage(_ e: String) -> CGImage? {
        guard !e.isEmpty else { return nil }
        let font = NSFont(name: "AppleColorEmoji", size: 64) ?? .systemFont(ofSize: 64)
        let str = NSAttributedString(string: e, attributes: [.font: font])
        let ink = str.boundingRect(with: NSSize(width: 400, height: 400), options: [.usesDeviceMetrics, .usesLineFragmentOrigin])
        let side = ceil(max(ink.width, ink.height)) + 4
        let px = Int(side * 2)
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: 2, y: 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(at: NSPoint(x: (side - ink.width) / 2 - ink.minX, y: (side - ink.height) / 2 - ink.minY))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    static func statusText(_ s: WorkState) -> String {
        switch s {
        case .working: return "WORKING"
        case .yourTurn: return "YOUR TURN"
        case .needsYou: return "NEEDS YOU"
        case .running: return "RUNNING"
        case .none: return ""
        }
    }

    /// Strip parts covered by windows in front of the Terminal window, in local points.
    func setOccluders(_ rects: [CGRect]) {
        guard rects != occluders else { return }
        occluders = rects
        updateMask()
    }

    private func updateMask() {
        var path = StripMetrics.shape(bounds.size)
        if !occluders.isEmpty {
            let cut = CGMutablePath()
            for r in occluders { cut.addRect(r) }
            path = path.subtracting(cut, using: .winding)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.frame = bounds
        fill.frame = bounds
        let dull = model.state != .working && model.state != .needsYou
        let key = "\(model.color)-\(dull)-\(Int(bounds.width))-\(Int(bounds.height))"
        if key != fillKey {
            // Working strips are bright; everything else fades to a dull version.
            if !fillKey.isEmpty, fillKey.hasPrefix("\(model.color)-") {
                let t = CATransition()
                t.type = .fade
                t.duration = 0.45
                fill.add(t, forKey: "dim")
            }
            fillKey = key
            fill.contents = Dither.strip(size: bounds.size, color: model.color, fade: 0.01, dull: dull)
        }
        updateMask()

        let h = bounds.height
        let pad: CGFloat = 12
        // status, right aligned
        let statusText = Self.statusText(model.state) as NSString
        let statusW = statusText.length == 0 ? 0 : ceil(statusText.size(withAttributes: [.font: Fonts.pixel(12)]).width) + 2
        let dotsW: CGFloat = model.state == .none || model.state == .running ? 0 : 8 + 7
        let emojiSlot: CGFloat = model.emoji.isEmpty ? 0 : 20 + (statusW > 0 ? 6 : 0)
        emojiLayer.frame = CGRect(x: bounds.width - pad - 18, y: (h - 18) / 2, width: 18, height: 18)
        let statusX = bounds.width - pad - emojiSlot - statusW
        statusLayer.frame = CGRect(x: statusX, y: (h - 15) / 2 - 1, width: statusW, height: 15)
        let cellS: CGFloat = 3, gap: CGFloat = 2
        let gx = statusX - dotsW, gy = (h - (cellS * 2 + gap)) / 2
        for (i, d) in dots.enumerated() {
            let cx = i % 2, cy = i / 2
            d.frame = CGRect(x: gx + CGFloat(cx) * (cellS + gap), y: gy + CGFloat(1 - cy) * (cellS + gap), width: cellS, height: cellS)
            d.isHidden = dotsW == 0
        }
        let statusLeft = statusW > 0 ? gx - 16 : bounds.width - pad - emojiSlot - 8

        // name and subtitle
        let nameX = StripMetrics.fade
        let nameFull = ceil((model.name as NSString).size(withAttributes: [.font: Fonts.geist(17, "SemiBold")]).width) + 2
        let chevW: CGFloat = 14
        let nameW = max(0, min(nameFull, statusLeft - nameX - chevW))
        nameLayer.frame = CGRect(x: nameX, y: (h - 22) / 2, width: nameW, height: 22)
        chevron.frame = CGRect(x: nameX + nameW + 4, y: (h - 6) / 2, width: 9, height: 6)
        controlRect = CGRect(x: nameX - 8, y: 0, width: nameW + chevW + 14, height: h)
        let subX = nameX + nameW + chevW + 10
        let subW = statusLeft - subX
        subLayer.isHidden = model.subtitle.isEmpty || subW < 50
        subLayer.frame = CGRect(x: subX, y: (h - 16) / 2 - 1, width: max(0, subW), height: 16)

        shimmer.frame = CGRect(x: 0, y: 0, width: 140, height: h)
        if shimmer.contents == nil { shimmer.contents = Dither.shimmer(width: 140, height: h) }
        if model.state == .working, abs(shimmerWidth - bounds.width) > 1 {
            shimmer.removeAnimation(forKey: "sweep")
            startShimmer()
        }
        CATransaction.commit()
    }

    private func applyState() {
        for d in dots { d.removeAllAnimations(); d.opacity = 1 }
        switch model.state {
        case .working, .needsYou:
            // One lit cell walks the 2x2 grid clockwise.
            let order = [0, 1, 3, 2]
            for (step, idx) in order.enumerated() {
                let a = CAKeyframeAnimation(keyPath: "opacity")
                a.values = [1, 0.28, 0.28, 0.28, 1]
                a.keyTimes = [0, 0.25, 0.5, 0.75, 1]
                a.duration = 0.9
                a.calculationMode = .discrete
                a.repeatCount = .infinity
                a.timeOffset = 0.9 - Double(step) * 0.225
                dots[idx].add(a, forKey: "spin")
            }
            startShimmer()
        case .yourTurn:
            shimmer.removeAllAnimations()
            shimmer.isHidden = true
        default:
            shimmer.removeAllAnimations()
            shimmer.isHidden = true
        }
    }

    private func startShimmer() {
        guard shimmer.animation(forKey: "sweep") == nil, bounds.width > 0 else { return }
        shimmer.isHidden = false
        shimmerWidth = bounds.width
        let sweep = max(1.4, Double(bounds.width) / 600)
        let a = CABasicAnimation(keyPath: "position.x")
        a.fromValue = -70
        a.toValue = bounds.width + 70
        a.duration = sweep
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.55, 1)
        let g = CAAnimationGroup()
        g.animations = [a]
        g.duration = sweep + 1.2
        g.repeatCount = .infinity
        shimmer.position.x = -200
        shimmer.add(g, forKey: "sweep")
    }

    /// The strip dissolves in from the left, dither cell by dither cell.
    func playEntrance() {
        let m = CAGradientLayer()
        m.frame = bounds
        m.startPoint = CGPoint(x: 0, y: 0.5)
        m.endPoint = CGPoint(x: 1, y: 0.5)
        m.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        m.locations = [0, 0, 0.001]
        layer?.mask = m
        let a = CABasicAnimation(keyPath: "locations")
        a.fromValue = [0, 0, 0.001]
        a.toValue = [0, 1, 1.15]
        a.duration = 0.42
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.layer?.mask = nil }
        m.add(a, forKey: "reveal")
        CATransaction.commit()
    }
}

