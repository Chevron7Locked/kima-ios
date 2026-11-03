import SwiftUI

/// Picks the player's accent from the playing track's map colour.
/// A track with a colour gets the logo-gradient accent for that colour; a track without one
/// (production today, audiobooks, podcasts, tracks not yet on the map) gets brand amber.
enum PlayerAccentResolver {
    static func resolve(
        trackId: String?,
        colour: (String) -> Double?
    ) -> (accent: FilamentAccent, hasColour: Bool) {
        guard let trackId, let value = colour(trackId) else { return (.brand, false) }
        return (FilamentAccent(colour: value), true)
    }
}
