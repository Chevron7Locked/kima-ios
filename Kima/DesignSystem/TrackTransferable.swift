import SwiftUI
import UniformTypeIdentifiers

// MARK: - Track drag-and-drop payload (drag playlist rows onto the Now Playing bar)
// One payload type for every draggable track surface. It transfers a whole Codable `Track` (playlist responses already
// carry full tracks, so drops need no network call) via the `.draggable`/`.dropDestination` Transferable pair.

extension UTType {
    /// In-app track drag payload (also exported as public.json + public.data).
    static let kimaTrack = UTType(exportedAs: "com.chevron7locked.kima.track")
}

struct TrackTransferable: Codable, Transferable {
    let track: Track

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .kimaTrack)
    }
}

// MARK: - Conditional track drag

/// Conditional `.draggable(TrackTransferable)` for track rows: dragging onto the Now Playing bar queues the track next.
/// `enabled: false` makes the row undraggable (missing/discovery rows carry no library track id). Applied via
/// `.modifier(...)` because `isActive:` overloads have proven brittle across SDKs.
struct TrackDragModifier: ViewModifier {
    let track: Track
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(TrackTransferable(track: track))
        } else {
            content
        }
    }
}