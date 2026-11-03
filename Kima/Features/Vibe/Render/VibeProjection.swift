import CoreGraphics
import Foundation
import Observation
import simd
import UIKit

/// Where the map's text sits on screen right now: the mood labels and the few stars the overlay marks
/// (the selected one). The Metal layer refreshes it whenever the camera moves or the
/// tracked stars change; the overlay only reads it. Main thread only.
@Observable
final class VibeProjection {
    struct Label: Identifiable {
        let id: String
        let text: String
        let centre: CGPoint
        let visible: Bool
    }

    /// A star's place on screen. `centre` is in view points.
    struct Marker {
        let centre: CGPoint
        let inFront: Bool
    }

    // Read by the overlay.
    private(set) var labels: [Label] = []
    private(set) var markers: [String: Marker] = [:]
    private(set) var isOverview = true
    private(set) var viewSize: CGSize = .zero

    // Set by the Metal layer; not observed, picked up on the next tick.
    @ObservationIgnored private var anchors: [VibeMoodAnchor] = []
    @ObservationIgnored private var trackedIds: [String] = []
    @ObservationIgnored private var configDirty = true
    @ObservationIgnored private var lastViewProjection: simd_float4x4?
    @ObservationIgnored private var lastViewSize: CGSize = .zero
    @ObservationIgnored private var lastOverview = true

    /// The mood labels for a map (call when a different map arrives).
    func setAnchors(for tracks: [VibeMapTrack]) {
        anchors = VibeMoodAnchors.compute(tracks: tracks)
        configDirty = true
    }

    /// Stars the overlay needs screen positions for.
    func setTracked(_ ids: [String]) {
        guard ids != trackedIds else { return }
        trackedIds = ids
        configDirty = true
    }

    /// Refresh from the camera. Does nothing when neither the pose, the size nor the tracked set changed.
    func tick(viewProjection vp: simd_float4x4, viewSize size: CGSize, overview: Bool,
              position: (String) -> SIMD3<Float>?) {
        let moved = lastViewProjection.map { !simd_equal($0, vp) } ?? true
        guard moved || configDirty || size != lastViewSize || overview != lastOverview else { return }
        lastViewProjection = vp
        lastViewSize = size
        lastOverview = overview
        configDirty = false

        let items = anchors.map {
            VibeLabelLayout.item(world: $0.world, viewProjection: vp, viewSize: size, size: Self.labelSize($0.label))
        }
        let shown = VibeLabelLayout.visibility(items)
        labels = (0..<anchors.count).map { i in
            Label(id: anchors[i].mood, text: anchors[i].label, centre: items[i].centre, visible: shown[i])
        }
        var out = [String: Marker]()
        for id in trackedIds {
            guard let world = position(id) else { continue }
            let it = VibeLabelLayout.item(world: world, viewProjection: vp, viewSize: size, size: .zero)
            out[id] = Marker(centre: it.centre, inFront: it.inFront)
        }
        markers = out
        isOverview = overview
        viewSize = size
    }

    // MARK: Label box

    static let labelFontSize: CGFloat = 11
    static let labelTracking: CGFloat = 0.16 * labelFontSize
    static let labelPadX: CGFloat = 8
    static let labelPadY: CGFloat = 3

    /// The box a label occupies, for overlap checks: text width plus tracking plus padding.
    static func labelSize(_ text: String) -> CGSize {
        let font = UIFont(name: "Montserrat-Medium", size: labelFontSize) ?? .systemFont(ofSize: labelFontSize, weight: .medium)
        let w = (text as NSString).size(withAttributes: [.font: font]).width + labelTracking * CGFloat(text.count)
        return CGSize(width: ceil(w) + labelPadX * 2, height: ceil(font.lineHeight) + labelPadY * 2)
    }
}
