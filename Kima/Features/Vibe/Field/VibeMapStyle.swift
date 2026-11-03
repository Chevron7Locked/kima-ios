import Foundation
import simd

/// Every switch and constant that decides how the 3-d vibe map looks, in one place.
/// Flip a flag here to bring back a web behaviour that was left out on purpose.
enum VibeMapStyle {
    /// The one amber, the app brand colour `#c98f3f` (not the web's older `#fca200`).
    static let amberHex: UInt32 = 0xc98f3f
    static var amber: SIMD3<Float> { linear(hex: amberHex) }
    /// Ring on the track that started the queue (song path, play similar) or the show-similar source, in
    /// starlight: the queue header already says what built it, and amber stays rare. Blend has none.
    static func operationRing(_ kind: VibeOperationKind) -> SIMD3<Float>? {
        kind == .blend ? nil : starlight
    }
    /// Colour of the thread drawn through the queue.
    static let queueHex: UInt32 = 0xc9b184
    static var queue: SIMD3<Float> { linear(hex: queueHex) }
    /// Starlight, `#f3ecdd`.
    static let starHex: UInt32 = 0xf3ecdd
    static var starlight: SIMD3<Float> { linear(hex: starHex) }
    /// Far background stars, cool white `#dde3f5`.
    static var farCool: SIMD3<Float> { linear(hex: 0xdde3f5) }

    // MARK: Galaxy look (every number in one place)

    /// Camera polar angle at home, radians from straight down (32.9 degrees).
    static let homePolar: Float = 0.574
    /// Share of the half-screen the framed stars may reach, across and up.
    static let fillAcross: Float = 0.92
    static let fillUp: Float = 0.80
    static let framePercentile = 0.95
    /// Home distance never exceeds this times the distance that fits 80% of the stars.
    static let frameTailCap: Float = 1.5
    static let minDistanceFactor: Float = 0.12
    static let overviewFactor: Float = 0.62
    static let locateFactor: Float = 0.28
    /// Star size scale, 118 / 113.
    static let starSizeK: Float = 1.0443
    static let starMinPt: Float = 1.1
    /// A star's sprite never exceeds this many points; reached by zooming in (the web's 40 px at dpr 2).
    static let starMaxPt: Float = 20
    /// Growth toward the camera is uncapped as on the web (1 / depth); this only guards against a
    /// star passing through the camera. The size clamp above binds long before it.
    static let starGrowthCap: Float = 64
    static let notableShare = 0.11
    static let starColourScale: Float = 0.5
    static let farStarCount = 4096
    /// A flat map keeps its polar angle inside this range.
    static let flatPolarRange: ClosedRange<Float> = 0.26...0.98

    /// Ring offsets from the star's disc, in screen points (gap, stroke width): a ring sits a fixed
    /// gap outside the disc and grows with the star as the camera zooms (the web's GAP / fitRing).
    static let ringPlaying: (gap: Float, width: Float) = (6.5, 1.25)
    static let ringSelectedWhite: (gap: Float, width: Float) = (3, 1)
    static let ringSelectedAmber: (gap: Float, width: Float) = (6.5, 1.25)
    /// Dark band under the playing ring when the selection is the same star, so the white stays legible
    /// over stars tinted gold or amber.
    static let ringSelectedMoat: (gap: Float, width: Float) = (1.5, 2)
    static let ringOperation: (gap: Float, width: Float) = (10, 1)
    /// The moat's colour, the map's ink `#08050e`.
    static var ink: SIMD3<Float> { linear(hex: 0x08050e) }
    /// Song path ends: a ring round each, outside the selection's rings, and a filled dot inside the
    /// end's ring (the dot is a fixed mark at the centre, not tied to the disc).
    static let ringPathEnd: (gap: Float, width: Float) = (10, 1)
    static let pathEndDot: (gap: Float, width: Float) = (3, -1)
    /// The queue's first songs wear a thin gold ring (the web's CHART_RINGED).
    static let ringQueued: (gap: Float, width: Float) = (4.5, 0.75)
    /// A queued ring is skipped when its star's centre lands within this many points of an earlier
    /// queued star's centre (the web's crowded-song rule).
    static let ringQueuedMinStarSpacing: Float = 12.5

    /// Star core radius as a share of the sprite radius.
    static let coreShare: Float = 0.36
    /// Core radius never under this many pixels (also sets the zoom-out limit).
    static let coreMinPx: Float = 1.1
    /// Half-width of the core's soft edge, device pixels (the web's 2 px anti-aliased edge).
    static let edgePx: Float = 1.0
    /// The halo fades across the whole sprite, power 3, at the web's 0.22 strength — a light glow,
    /// so the core reads as a point of light rather than a blob.
    static let haloReach: Float = 1.0
    static let haloPower: Float = 3
    static let haloStrength: Float = 0.22
    /// Brightness range of the faint majority of stars.
    static let faintLow: Float = 0.24
    static let faintHigh: Float = 0.48

    // MARK: Queue chart (the dotted thread through the queue)

    /// Dots sit this far apart on screen (points); closer dots are thinned by the shader's LOD.
    static let chartSpacingPt: Float = 5.5
    /// Dot diameter, points.
    static let chartDotPt: Float = 1.5
    /// Dots step along a segment every 0.15 of the field's base star size (world units).
    static let chartStepFactor: Float = 0.15
    /// A segment's stipple reaches this many world units out of each end star, then fades out.
    static let chartReach: Float = 3.6
    /// How far along the queue the thread runs ahead / back, and how many ahead songs are ringed.
    static let chartAhead = 60
    static let chartBehind = 3
    static let chartRinged = 8
    /// Near dots at full strength fade to this by the 60th song ahead.
    static let chartAlphaNear: Float = 0.62
    static let chartAlphaFar: Float = 0.14
    static let chartAlphaLast = 8
    static let chartAlphaFade: Float = 52
    /// The played part of the queue, thin: 0.2 × (1 + (order+1)/3) per web.
    static let chartPlayedBase: Float = 0.2
    /// Dots stop this far (points) outside an end star's disc, per kind of song.
    static let chartClearQueued: Float = 7.5
    static let chartClearPlaying: Float = 11
    static let chartClearSelected: Float = 10.5
    static let chartClearOperation: Float = 13
    /// The song path's starlight row between its two ends.
    static let pathChordAlpha: Float = 0.22

    /// Distance in points two stars must keep for their solid cores to read as two points.
    static func separationPoints(pxPerPt: Float) -> Float {
        (2 * coreMinPx + 1) / pxPerPt
    }

    /// Convert a 0xRRGGBB colour to linear light.
    static func linear(hex: UInt32) -> SIMD3<Float> {
        func lin(_ shift: UInt32) -> Float {
            let s = Float((hex >> shift) & 0xff) / 255
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return SIMD3(lin(16), lin(8), lin(0))
    }
}
