import SwiftUI
import UIKit

/// Palette of three colors extracted from a cover-art image by sampling a 32×32 pixel grid and clustering by HSB.
/// All three are sRGB and safe to interpolate in SwiftUI gradients.
struct CoverArtPalette: Sendable, Equatable {
    /// Most saturated and prominent color — used for gradient top stop (opacity 0.3–0.4).
    let vibrant: Color
    /// Saturated but darker — gradient middle stop (opacity 0.6).
    let darkVibrant: Color
    /// Low-saturation dark — gradient lower stop (opacity 0.9) before hard base color.
    let darkMuted: Color
}

// MARK: - Palette cache

/// In-memory palette cache for extracted palettes, bounded to 50 entries.
/// Eviction removes an arbitrary entry when the limit is reached (not true LRU).
/// Actor isolation makes it safe under Swift 6 strict concurrency.
private actor PaletteCache {
    static let shared = PaletteCache()
    private var store: [String: CoverArtPalette] = [:]
    private let maxEntries = 50

    func get(_ key: String) -> CoverArtPalette? { store[key] }

    func set(_ key: String, _ value: CoverArtPalette) {
        if store.count >= maxEntries, let evict = store.keys.first {
            store.removeValue(forKey: evict)
        }
        store[key] = value
    }
}

/// Async cover-art palette extraction: `palette(coverId:server:)` fetches the cover at 300 px and
/// samples pixels on a detached utility task (main actor never blocked). Cached in memory (50
/// entries by coverId). Returns nil if the image can't be fetched; callers keep their fallback gradient.
enum CoverArtColor {

    // MARK: - Public API (C1 contract)

    /// Fetch the palette for a cover-art identifier. Returns nil on any failure (bad URL, network error, unsamplable
    /// image). Cached per coverId, so repeat calls are free. `ImageCache.shared` attaches auth for our server host.
    static func palette(coverId: String?, server: KimaServer) async -> CoverArtPalette? {
        guard let coverId, !coverId.isEmpty else { return nil }

        // Composite key: server URL + coverId so switching servers never serves a stale palette.
        let cacheKey = "\(server.baseURL.absoluteString)|\(coverId)"

        // Cache check — avoids re-download on every view-appear.
        if let cached = await PaletteCache.shared.get(cacheKey) { return cached }

        guard let url = CoverArtURL.url(base: server, coverId: coverId, size: 300) else {
            return nil
        }

        // Reuse bytes already held in ImageCache — avoids a duplicate download when
        // CoverArtImage already fetched the same URL at a similar size.
        guard let uiImage = try? await ImageCache.shared.fetch(url: url),
              let cgImage = uiImage.cgImage else { return nil }

        // Pixel sampling on a 32×32 grid completes in microseconds — no detached task needed.
        // CGImage is not Sendable so it cannot cross to a detached task anyway.
        guard let result = extractPalette(from: cgImage) else { return nil }
        await PaletteCache.shared.set(cacheKey, result)
        return result
    }

    // MARK: - Pixel sampling

    private static func extractPalette(from cgImage: CGImage) -> CoverArtPalette? {
        let side = 32
        var raw = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &raw,
            width: side, height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        struct Pixel { let r, g, b, hue, sat, bright: Double }
        var pixels: [Pixel] = []
        pixels.reserveCapacity(side * side)

        for i in 0..<(side * side) {
            let o = i * 4
            let r = Double(raw[o]) / 255
            let g = Double(raw[o + 1]) / 255
            let b = Double(raw[o + 2]) / 255
            let (h, s, br) = hsb(r: r, g: g, b: b)
            // Skip near-grey (low saturation) and near-black (very low brightness)
            if s > 0.1 && br > 0.05 {
                pixels.append(Pixel(r: r, g: g, b: b, hue: h, sat: s, bright: br))
            }
        }

        guard !pixels.isEmpty else { return nil }

        // Vibrant: pixel with the highest saturation × brightness score
        let vib = pixels.max(by: { $0.sat * $0.bright < $1.sat * $1.bright })!

        // DarkVibrant: same hue family as vibrant, brightness < 0.55
        let darkVib: Pixel = pixels
            .filter { hueDelta($0.hue, vib.hue) < 0.25 && $0.bright < 0.55 }
            .max(by: { $0.sat * $0.bright < $1.sat * $1.bright })
            ?? pixels.filter { $0.bright < 0.55 }
                     .max(by: { $0.sat * $0.bright < $1.sat * $1.bright })
            ?? vib

        // DarkMuted: low saturation, dark — used as the gradient's lower stop
        let darkMut: Pixel = pixels
            .filter { $0.bright < 0.4 && $0.sat < 0.35 }
            .max(by: { $0.bright < $1.bright })
            ?? pixels.filter { $0.bright < 0.4 }
                     .max(by: { $0.sat * $0.bright < $1.sat * $1.bright })
            ?? darkVib

        return CoverArtPalette(
            vibrant:     Color(red: vib.r,     green: vib.g,     blue: vib.b),
            darkVibrant: Color(red: darkVib.r, green: darkVib.g, blue: darkVib.b),
            darkMuted:   Color(red: darkMut.r, green: darkMut.g, blue: darkMut.b)
        )
    }

    // MARK: - Color math

    /// Convert linear RGB to HSB (all values in [0,1]).
    private static func hsb(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b)
        let mn = min(r, g, b)
        let d  = mx - mn
        let brightness = mx
        let saturation = mx == 0 ? 0.0 : d / mx
        var hue = 0.0
        if d > 0 {
            switch mx {
            case r:  hue = ((g - b) / d).truncatingRemainder(dividingBy: 6)
            case g:  hue = (b - r) / d + 2
            default: hue = (r - g) / d + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, saturation, brightness)
    }

    /// Angular distance between two hues in [0,1] — accounts for wrap-around at 1→0.
    private static func hueDelta(_ h1: Double, _ h2: Double) -> Double {
        let d = abs(h1 - h2)
        return min(d, 1 - d)
    }
}
