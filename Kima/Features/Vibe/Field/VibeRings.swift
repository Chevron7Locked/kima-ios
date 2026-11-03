import CoreGraphics
import Foundation
import simd

/// A flat ring drawn round a star. Radii are screen points measured out from the star's own drawn
/// disc, so a ring tracks its star as zoom grows it (port of the web's `fitRing`).
struct VibeRing: Equatable {
    var centre: SIMD3<Float>
    /// Points.
    var outerRadius: Float
    var innerRadius: Float
    /// Linear-light colour.
    var colour: SIMD3<Float>
    var opacity: Float
    /// Opacity breathes (the playing ring), unless Reduce Motion or the still hook is on. Size always tracks the star.
    var breathes: Bool
}

/// What built the queue; picks the colour of the ring on its first star. A blend has no single first star, so no ring.
enum VibeOperationKind: String { case songPath, playSimilar, similar, blend }

enum VibeRings {
    /// All rings for one frame. Radii are screen points and need the camera: a star's drawn disc, and
    /// the on-screen distances that keep the queue's rings from crowding. `emph` is each star's
    /// current eased emphasis (its size factor), so rings follow the stars' eased growth.
    /// An id that is not on the map, or a star behind the camera, draws nothing.
    static func build(indexById: [String: Int], positions: [SIMD3<Float>], sizes: [Float], emph: [Float],
                      view: simd_float4x4, viewProj: simd_float4x4, viewSize: CGSize, home: Float,
                      operationSourceId: String?, playingId: String?, selectedId: String?,
                      operationKind: VibeOperationKind = .songPath,
                      pathStartId: String? = nil, pathEndId: String? = nil,
                      queueIds: [String] = []) -> [VibeRing] {
        guard viewSize.width > 0, viewSize.height > 0, home > 0,
              sizes.count == positions.count, emph.count == positions.count else { return [] }
        func slot(_ id: String?) -> Int? { id.flatMap { indexById[$0] } }
        func depth(_ i: Int) -> Float? {
            let v = simd_mul(view, SIMD4<Float>(positions[i], 1))
            return v.w > 1e-4 ? -v.z : nil
        }
        func screenPt(_ i: Int) -> CGPoint? {
            let it = VibeLabelLayout.item(world: positions[i], viewProjection: viewProj, viewSize: viewSize, size: .zero)
            return it.inFront ? it.centre : nil
        }
        /// The star's crisp core radius on screen, points — the disc a ring sits a gap outside of.
        func discPt(_ i: Int, _ d: Float) -> Float {
            VibeStarMetrics.pointSizePt(size: sizes[i], depth: d, home: home, emph: emph[i])
                * 0.5 * VibeMapStyle.coreShare
        }
        func ring(_ i: Int, gap: (gap: Float, width: Float), colour: SIMD3<Float>,
                  opacity: Float, breathes: Bool = false) -> VibeRing? {
            guard let d = depth(i) else { return nil }
            let centreline = discPt(i, d) + gap.gap
            return VibeRing(centre: positions[i], outerRadius: centreline + gap.width / 2,
                            innerRadius: max(0, centreline - gap.width / 2),
                            colour: colour, opacity: opacity, breathes: breathes)
        }

        var out = [VibeRing]()
        var drawn: [(at: CGPoint, r: Float)] = []   // screen centre and centreline of every ring so far
        func add(_ r: VibeRing?, at i: Int) {
            guard let r, let at = screenPt(i) else { return }
            out.append(r)
            drawn.append((at: at, r: (r.outerRadius + r.innerRadius) * 0.5))
        }

        if let i = slot(operationSourceId), let colour = VibeMapStyle.operationRing(operationKind) {
            add(ring(i, gap: VibeMapStyle.ringOperation, colour: colour, opacity: 0.45), at: i)
        }
        for id in [pathStartId, pathEndId] {
            if let i = slot(id) {
                add(ring(i, gap: VibeMapStyle.ringPathEnd, colour: VibeMapStyle.starlight, opacity: 0.8), at: i)
            }
        }
        // The path end's filled centre dot (a fixed mark, not tied to the disc).
        if let i = slot(pathEndId), depth(i) != nil {
            out.append(VibeRing(centre: positions[i], outerRadius: VibeMapStyle.pathEndDot.gap,
                                innerRadius: -1, colour: VibeMapStyle.starlight, opacity: 0.9, breathes: false))
        }
        // The selection's dark moat goes under the playing ring, which can sit on the same star.
        if let i = slot(selectedId) {
            add(ring(i, gap: VibeMapStyle.ringSelectedMoat, colour: VibeMapStyle.ink, opacity: 0.6), at: i)
        }
        if let i = slot(playingId) {
            add(ring(i, gap: VibeMapStyle.ringPlaying, colour: VibeMapStyle.amber, opacity: 0.7, breathes: true), at: i)
        }
        if let i = slot(selectedId) {
            add(ring(i, gap: VibeMapStyle.ringSelectedWhite, colour: SIMD3(1, 1, 1), opacity: 0.7), at: i)
            add(ring(i, gap: VibeMapStyle.ringSelectedAmber, colour: VibeMapStyle.amber, opacity: 0.7), at: i)
        }

        // The queue's first songs, ringed thin gold and fading with their order down the queue.
        // A ring is left off where it crosses a ring already drawn, where it crosses a nearer
        // queued song's ring, and where its song sits crowded against an earlier queued song
        // (the web's `QueueRings`).
        let onMap = queueIds.compactMap { indexById[$0] }
        if onMap.count > 1 {
            // The queue's own order decides who is "ahead": the songs after the playing one.
            let origin = playingId.flatMap { indexById[$0] }.flatMap { pid in onMap.firstIndex(of: pid) } ?? -1
            let a = max(0, origin)
            let ahead = min(VibeMapStyle.chartRinged, max(0, onMap.count - a - 1))
            var placed: [(at: CGPoint, r: Float)] = []
            var songCentres: [CGPoint] = []
            for o in 1...max(1, ahead) where o <= ahead {
                let i = onMap[a + o]
                if i == slot(playingId) || i == slot(selectedId) { continue }
                guard let d = depth(i), let at = screenPt(i) else { continue }
                let r = discPt(i, d) + VibeMapStyle.ringQueued.gap
                let crowded = drawn.contains { hypot($0.at.x - at.x, $0.at.y - at.y) < CGFloat(r + $0.r + 2) }
                    || placed.contains { hypot($0.at.x - at.x, $0.at.y - at.y) < CGFloat(r + $0.r + 1) }
                    || songCentres.contains { hypot($0.x - at.x, $0.y - at.y) < CGFloat(VibeMapStyle.ringQueuedMinStarSpacing) }
                if crowded { continue }
                out.append(VibeRing(centre: positions[i],
                                    outerRadius: r + VibeMapStyle.ringQueued.width / 2,
                                    innerRadius: max(0, r - VibeMapStyle.ringQueued.width / 2),
                                    colour: VibeMapStyle.queue, opacity: 0.5 - Float(o) * 0.03,
                                    breathes: false))
                placed.append((at: at, r: r))
                songCentres.append(at)
            }
        }
        return out
    }

    /// Opacity of the playing ring: 0.55 to 0.75 over 3.2 seconds; a steady 0.7 under Reduce Motion.
    static func breathOpacity(time t: Float, reduceMotion: Bool) -> Float {
        reduceMotion ? 0.7 : 0.55 + 0.20 * (0.5 + 0.5 * sin(2 * .pi * t / 3.2))
    }
}
