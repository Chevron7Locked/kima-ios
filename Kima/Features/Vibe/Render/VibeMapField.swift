import SwiftUI

/// The map as SwiftUI sees it: the Metal layer, the map's text overlay (`VibeMapOverlay`),
/// and (DEBUG) an invisible accessibility element UI tests can tap.
struct VibeMapField: View {
    let tracks: [VibeMapTrack]
    let mapKey: String
    let mapGeneration: Int
    let highlightedIds: [String]
    let operationSourceId: String?
    let operationKind: VibeOperationKind
    let focusMood: String?
    let selectedId: String?
    /// The song path's ends while its panel is open.
    let pathStartId: String?
    let pathEndId: String?
    /// The readout's cover and the rail; the overlay draws a leader from the star to the cover.
    let leader: VibeLeaderTarget?
    /// Where the map's mood labels may show (between the search list and the bottom stack).
    let labelBand: VibeLabelBand
    let playingId: String?
    let queueIds: [String]
    let locateTrigger: Int
    let homeTrigger: Int
    let flyTrigger: Int
    let flyToId: String?
    let onTap: (String?) -> Void
    let onDoubleTap: (String) -> Void
    let onLongPress: (String) -> Void

    @State private var projection = VibeProjection()
    /// The Metal renderer couldn't start; the error card replaces the black map.
    @State private var renderFailed = false
    /// Bumped by "try again" so SwiftUI builds a fresh Metal view.
    @State private var renderAttempt = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    @State private var debugStar: CGPoint?
    #endif

    var body: some View {
        ZStack {
            if renderFailed {
                KimaErrorState(message: "couldn't draw the map") {
                    renderFailed = false
                    renderAttempt += 1
                }
            } else {
                field
            }
        }
        .ignoresSafeArea()
    }

    private var field: some View {
        ZStack {
            VibeMetalLayer(
                input: VibeMapInput(
                    tracks: tracks, mapKey: mapKey, mapGeneration: mapGeneration,
                    highlightedIds: highlightedIds,
                    operationSourceId: operationSourceId, selectedId: selectedId,
                    playingId: playingId, queueIds: queueIds,
                    locateTrigger: locateTrigger, homeTrigger: homeTrigger,
                    flyTrigger: flyTrigger, flyToId: flyToId, reduceMotion: reduceMotion,
                    focusMood: focusMood, operationKind: operationKind,
                    pathStartId: pathStartId, pathEndId: pathEndId),
                projection: projection, trackedIds: trackedIds,
                onTap: onTap, onDoubleTap: onDoubleTap, onLongPress: onLongPress,
                onDebugStar: debugStarHandler,
                onRendererFailed: { renderFailed = true })
                .id(renderAttempt)
            if !VibeDebugFlags.bare {
                VibeMapOverlay(
                    projection: projection, selectedId: selectedId, leader: leader, highlightedIds: highlightedIds,
                    pathStartId: pathStartId, pathEndId: pathEndId, labelBand: labelBand)
            }
            #if DEBUG
            if let p = debugStar {
                Color.clear
                    .frame(width: 44, height: 44)
                    .position(p)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityIdentifier("vibe-debug-star")
            }
            #endif
        }
    }

    /// Stars the overlay needs screen positions for, without repeats.
    private var trackedIds: [String] {
        var seen = Set<String>()
        return [selectedId, pathStartId, pathEndId].compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    private var debugStarHandler: ((CGPoint?) -> Void)? {
        #if DEBUG
        return { p in debugStar = p }
        #else
        return nil
        #endif
    }
}
