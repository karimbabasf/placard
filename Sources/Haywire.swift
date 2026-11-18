import AppKit
import QuartzCore

/// Christmas mode: a chasing ring of pixel bulbs and a color-cycling frame around a
/// Terminal window whose agent is waiting on you. Never takes a click.
final class HaywirePanel: NSPanel {
    let view = HaywireView()
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary, .transient]
        contentView = view
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HaywireView: NSView {
    static let colors: [CGColor] = [0xD7263D, 0x18A558, 0xFFC53D, 0xF4F1EA].map {
        NSColor(srgbRed: CGFloat(($0 >> 16) & 0xFF) / 255, green: CGFloat(($0 >> 8) & 0xFF) / 255, blue: CGFloat($0 & 0xFF) / 255, alpha: 1).cgColor
    }
    private let root = CALayer()
    private let ring = CALayer()
    private let mask = CAShapeLayer()
    private var bulbs: [CALayer] = []
    private var built: CGSize = .zero
    private var occluders: [CGRect] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(root)
        root.mask = mask
        ring.borderWidth = 5
        ring.cornerRadius = StripMetrics.windowRadius
        ring.cornerCurve = .continuous
        root.addSublayer(ring)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setOccluders(_ rects: [CGRect]) {
        guard rects != occluders else { return }
        occluders = rects
        updateMask()
    }

    private func updateMask() {
        var path = CGPath(rect: bounds, transform: nil)
        if !occluders.isEmpty {
            let cut = CGMutablePath()
            for r in occluders { cut.addRect(r) }
            path = path.subtracting(cut, using: .winding)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.path = path
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = bounds
        ring.frame = bounds
        updateMask()
        CATransaction.commit()
        if abs(built.width - bounds.width) > 2 || abs(built.height - bounds.height) > 2 { rebuild() }
    }

    private func rebuild() {
        built = bounds.size
        bulbs.forEach { $0.removeFromSuperlayer() }
        bulbs = []

        let wash = CAKeyframeAnimation(keyPath: "borderColor")
        wash.values = Self.colors.prefix(3).map { $0.copy(alpha: 0.85)! }
        wash.calculationMode = .discrete
        wash.duration = 0.75
        wash.repeatCount = .infinity
        ring.add(wash, forKey: "wash")

        // Bulbs walk the perimeter just inside the frame.
        let inset: CGFloat = 9, step: CGFloat = 15, size: CGFloat = 4
        let r = bounds.insetBy(dx: inset, dy: inset)
        guard r.width > 20, r.height > 20 else { return }
        var points: [CGPoint] = []
        var x = r.minX
        while x <= r.maxX { points.append(CGPoint(x: x, y: r.maxY)); x += step }
        var y = r.maxY - step
        while y >= r.minY { points.append(CGPoint(x: r.maxX, y: y)); y -= step }
        x = r.maxX - step
        while x >= r.minX { points.append(CGPoint(x: x, y: r.minY)); x -= step }
        y = r.minY + step
        while y < r.maxY { points.append(CGPoint(x: r.minX, y: y)); y += step }

        let period = 0.6
        for (i, p) in points.enumerated() {
            let b = CALayer()
            b.frame = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            b.backgroundColor = Self.colors[i % 4]
            let a = CAKeyframeAnimation(keyPath: "backgroundColor")
            a.values = Self.colors
            a.calculationMode = .discrete
            a.duration = period
            a.repeatCount = .infinity
            a.timeOffset = Double(i % 4) * period / 4
            b.add(a, forKey: "chase")
            root.addSublayer(b)
            bulbs.append(b)
        }
    }
}
