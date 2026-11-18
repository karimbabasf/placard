import AppKit

/// Ordered (Bayer 4x4) dither textures. One texture cell = `cell` points,
/// drawn with nearest-neighbour scaling so the pixels stay crisp.
enum Dither {
    static let cell: CGFloat = 2

    private static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 }
    static func threshold(_ x: Int, _ y: Int) -> Double { bayer[(y & 3) * 4 + (x & 3)] }

    private static func image(cols: Int, rows: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> CGImage? {
        var data = [UInt8](repeating: 0, count: cols * rows * 4)
        for y in 0..<rows {
            for x in 0..<cols {
                let (r, g, b, a) = pixel(x, y)
                let i = (y * cols + x) * 4
                // premultiplied alpha
                data[i] = UInt8(Int(r) * Int(a) / 255)
                data[i + 1] = UInt8(Int(g) * Int(a) / 255)
                data[i + 2] = UInt8(Int(b) * Int(a) / 255)
                data[i + 3] = a
            }
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: cols, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: cols * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (UInt8, UInt8, UInt8) {
        (UInt8(((a.0 * (1 - t)) + b.0 * t) * 255), UInt8(((a.1 * (1 - t)) + b.1 * t) * 255), UInt8(((a.2 * (1 - t)) + b.2 * t) * 255))
    }

    /// Strip fill: a two-tone dithered vertical gradient of the group color that
    /// dissolves into the native title bar over the first `fade` points.
    static func strip(size: CGSize, color: Int, fade: CGFloat) -> CGImage? {
        let cols = max(1, Int(ceil(size.width / cell)))
        let rows = max(1, Int(ceil(size.height / cell)))
        let base = Palette.rgb(color)
        let top = mix(base, (1, 1, 1), 0.10)
        let bottom = mix(base, (0, 0, 0), 0.14)
        let fadeCols = max(1, Double(fade / cell))
        return image(cols: cols, rows: rows) { x, y in
            let th = threshold(x, y)
            let t = Double(y) / Double(max(1, rows - 1))      // 0 at top of the image
            let c = th < t ? bottom : top
            let reveal = Double(x) / fadeCols
            let a: UInt8 = th < reveal ? 255 : 0
            return (c.0, c.1, c.2, a)
        }
    }

    /// A soft band of light, dithered, swept across the strip while the window works.
    static func shimmer(width: CGFloat, height: CGFloat) -> CGImage? {
        let cols = max(1, Int(ceil(width / cell)))
        let rows = max(1, Int(ceil(height / cell)))
        return image(cols: cols, rows: rows) { x, y in
            let u = (Double(x) / Double(cols - 1)) * 2 - 1          // -1...1
            let bell = max(0, 1 - u * u) * 0.5
            return threshold(x, y) < bell ? (255, 255, 255, 46) : (0, 0, 0, 0)
        }
    }

    /// Tiny swatch-sized dither of a color, for menus and the prompt.
    static func swatch(size: CGSize, color: Int) -> CGImage? { strip(size: size, color: color, fade: 0.01) }
}
