import SwiftUI

/// The full player's one sanctioned glow: a soft wash of the song's map colour falling from the
/// top of the screen. Absent when the playing track has no colour.
struct PlayerAccentGlow: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        GeometryReader { geo in
            if env.accentHasColour {
                RadialGradient(
                    colors: [env.accent.color.opacity(0.16), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: geo.size.height * 0.75
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
