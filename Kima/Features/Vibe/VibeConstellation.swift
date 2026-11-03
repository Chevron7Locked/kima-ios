import SwiftUI

// MARK: - VibeConstellation

/// The user's Vibe Map as an ambient monochrome 3-D constellation: every track a star at its map position, inside
/// a stationary deep-field starfield (gentle twinkle only). Only the constellation tumbles (yaw spin plus a pitch
/// nod, with perspective). Reads a snapshot of the map tracks; the field renders before tracks arrive. Drawn on a
/// `Canvas` in `TimelineView(.animation)`; non-interactive and accessibility-hidden.
struct VibeConstellation: View {
    var tracks: [VibeMapTrack]
    /// Identity of the loaded map; the star cache rebuilds when it changes.
    var mapKey: String? = nil
    /// Monochrome by design — the map's colour is dropped in favour of a silver-bone starfield.
    var starColor: Color = KimaColor.textPrimary
    /// Perf cap; tracks beyond this are evenly sampled so density (clusters) is preserved.
    var maxStars: Int = 520

    /// Per-track 3-D base (flat position, depth seed, energy) — invariant across frames, rebuilt
    /// only when `tracks` changes (see `.onChange` below). `TimelineView(.animation)` re-evaluates
    /// `body` every tick, so a plain computed value here would redo the per-track depth `sin()`
    /// hash for up to 520 stars every frame; `@State` persists the cache across ticks instead.
    @State private var starBases: [StarBase] = []

    /// Reduce Motion: freeze to a single static frame instead of the continuous tumble.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { ctx, size in render(&ctx, size: size, t: 0) }
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, size in
                        render(&ctx, size: size, t: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Rebuild when the map changes (its key covers a same-count reload).
        .onChange(of: mapKey, initial: true) { _, _ in
            rebuildStarBases()
        }
    }

    // MARK: - Deep-field background

    private struct BGStar { let x, y, mag, phase: Double }

    /// A faint scatter of distant stars filling the frame, generated **once** from a deterministic
    /// hash and shared across instances. Fixed positions — this is the still sky the user's
    /// constellation rotates against. It's a large pool; `render` draws a subset sized to the
    /// canvas area so the density looks the same on iPhone and the much larger iPad screen.
    private static let backgroundField: [BGStar] = {
        var stars: [BGStar] = []
        stars.reserveCapacity(1000)
        var s = 12.9898
        func rnd() -> Double { s += 1.0; let v = sin(s * 78.233) * 43758.5453; return v - v.rounded(.down) }
        for _ in 0..<1000 {
            stars.append(BGStar(
                x: (rnd() - 0.5) * 2.2,     // spans well past the frame edges (full-bleed)
                y: (rnd() - 0.5) * 2.2,
                mag: rnd(),
                phase: rnd()
            ))
        }
        return stars
    }()

    // MARK: - Constellation cache

    private struct StarBase { let px, py, pz, seed, energy: Double }

    /// Samples `tracks` down to `maxStars` (same stride as before) and precomputes each star's flat
    /// position, positional depth seed, and energy — the per-track inputs to the per-frame rotation
    /// in `render`. These are pure functions of `tr.x`/`tr.y`, static for the lifetime of a given
    /// `tracks` snapshot, so they're computed once here instead of via `sin()` every frame.
    private func rebuildStarBases() {
        let stride = max(1, Int((Double(tracks.count) / Double(maxStars)).rounded(.up)))
        var bases: [StarBase] = []
        bases.reserveCapacity(min(tracks.count, maxStars))
        var i = 0
        while i < tracks.count {
            let tr = tracks[i]
            i += stride

            let px = tr.x - 0.5
            let py = tr.y - 0.5
            let seed = tr.x * 53.13 + tr.y * 97.71
            let pz = tr.z - 0.5
            let energy = tr.energy ?? tr.moodScore
            bases.append(StarBase(px: px, py: py, pz: pz, seed: seed, energy: energy))
        }
        starBases = bases
    }

    // MARK: - Render

    private func render(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }

        let swell = 0.82 + 0.18 * sin(t * 0.11)
        let cx = w * 0.5, cy = h * 0.5

        // 1) Deep background field — STATIONARY. Fixed positions, gentle twinkle only, so the
        //    constellation turns against a still night sky rather than the whole scene spinning.
        //    Count scales with canvas area → equal density on iPhone and the larger iPad screen
        //    (otherwise the central cluster reads as a lone box floating in empty space).
        let bgSpanX = w * 0.5, bgSpanY = h * 0.5
        let bgCount = min(Self.backgroundField.count, max(240, Int((w * h) / 1200)))
        for k in 0..<bgCount {
            let bg = Self.backgroundField[k]
            let sx = cx + bg.x * bgSpanX
            let sy = cy + bg.y * bgSpanY
            guard sx > -4, sx < w + 4, sy > -4, sy < h + 4 else { continue }

            let tw = 0.4 + 0.6 * (0.5 + 0.5 * sin(t * 0.5 + bg.phase * 6.2832))
            let sz = 0.55 + bg.mag * 0.7
            let op = min(0.5, (0.14 + 0.30 * bg.mag) * (0.5 + 0.5 * tw) * swell)
            ctx.fill(Path(ellipseIn: CGRect(x: sx - sz, y: sy - sz, width: sz * 2, height: sz * 2)),
                     with: .color(starColor.opacity(op)))
        }

        // 2) The user's constellation — a *slow* 3-D tumble (yaw spin + gentle pitch nod) with
        //    perspective, so near track-stars sweep wider/brighter while far ones recede.
        guard !starBases.isEmpty else { return }
        let yaw   = t * 0.024                 // ≈ 260 s per full turn — deliberately unhurried
        let pitch = 0.07 * sin(t * 0.018)
        let cosY = cos(yaw),   sinY = sin(yaw)
        let cosP = cos(pitch), sinP = sin(pitch)
        let spanX = w * 0.5, spanY = h * 0.5
        let focal = 2.0
        let Rt = 0.72                          // track depth extent, for the near/far brightness cue

        for base in starBases {
            // Centre the map position, then give each star a stable depth from a positional hash
            // so the flat map becomes a 3-D cloud (clusters keep their relative shape) — precomputed
            // in `rebuildStarBases()`, since it depends only on the track's fixed position.
            let rx  = base.px * cosY + base.pz * sinY
            let rzY = -base.px * sinY + base.pz * cosY
            let ry  = base.py * cosP - rzY * sinP
            let rz  = base.py * sinP + rzY * cosP
            let persp = focal / (focal + rz)
            let sx = cx + rx * spanX * persp
            let sy = cy + ry * spanY * persp

            // Per-star twinkle, phase seeded from position so it's stable frame to frame.
            let tw = 0.42 + 0.58 * (0.5 + 0.5 * sin(t * 0.6 + base.seed * 6.2832))
            let depth = min(1.0, max(0.0, (Rt - rz) / (2 * Rt)))
            let sz = (0.7 + base.energy * 0.9) * (0.6 + 0.7 * depth)
            let op = min(1.0, (0.42 + 0.58 * depth) * (0.55 + 0.45 * tw) * swell)
            ctx.fill(Path(ellipseIn: CGRect(x: sx - sz, y: sy - sz, width: sz * 2, height: sz * 2)),
                     with: .color(starColor.opacity(op)))
        }
    }
}
