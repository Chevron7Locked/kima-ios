import Foundation
import Observation

// MARK: - Add-to-Playlist source

/// What the user asked to add to a playlist; `PlaylistPickerSheet` resolves it to track IDs when it appears.
/// `.tracks` are used directly; `.album` and `.artist` are fetched by id (every owned album's tracks for an artist).
/// `Identifiable` drives `.sheet(item:)` from `AppShellView`; `Equatable` comes from the stable `id`,
/// so `Track` itself need not be `Equatable`.
enum PlaylistAddSource: Equatable, Identifiable, Sendable {
    case tracks([Track])
    case album(id: String)
    case artist(id: String)

    var id: String {
        switch self {
        case .tracks(let tracks): return "tracks:" + tracks.map(\.id).joined(separator: ",")
        case .album(let id):      return "album:\(id)"
        case .artist(let id):     return "artist:\(id)"
        }
    }

    static func == (lhs: PlaylistAddSource, rhs: PlaylistAddSource) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - PlaylistPickerModel

/// App-wide presenter for the Add-to-Playlist sheet, held on `AppEnvironment` as `env.playlistPicker`
/// so any surface can call `present(.tracks([track]))` without passing closures down the view tree.
/// `AppShellView` observes `source` and hosts the sheet; setting `source` to `nil` tears it down.
@MainActor
@Observable
final class PlaylistPickerModel {
    /// Non-nil while the picker should be presented. Drives the app-level sheet.
    var source: PlaylistAddSource?

    /// Present the picker for the given source (replaces any in-flight selection).
    func present(_ source: PlaylistAddSource) {
        self.source = source
    }

    /// Dismiss the picker and clear the pending selection.
    func dismiss() {
        source = nil
    }
}
