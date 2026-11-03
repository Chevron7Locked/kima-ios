import Foundation

/// What a tap on the map should do.
enum VibeTapAction: Equatable {
    /// Fill the song path's next empty end (start, then end) with this track.
    case pickPathTrack(String)
    case select(String)
    case deselect
    /// Nothing changes: empty space while the song path waits for a star.
    case ignore
}

/// Pure tap routing.
enum VibeTapRouter {

    struct State {
        /// The song path is open with an end still empty, so a star fills it instead of selecting.
        var pickingPath: Bool
    }

    /// `trackId` is nil for a tap on empty space.
    static func action(for trackId: String?, state: State) -> VibeTapAction {
        if state.pickingPath {
            guard let id = trackId else { return .ignore }
            return .pickPathTrack(id)
        }
        guard let id = trackId else { return .deselect }
        return .select(id)
    }
}
