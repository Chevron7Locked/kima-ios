import SwiftUI

/// A pushed page that loads one thing: the screen ground, a loading or error state (both retry with `retry`) until
/// `phase` has loaded, then `loaded`. The navigation bar stays transparent, so only the back button shows.
struct KimaPhaseScreen<Value: Sendable, Loaded: View>: View {
    let phase: LoadPhase<Value>
    let retry: () -> Void
    @ViewBuilder let loaded: () -> Loaded

    var body: some View {
        ZStack {
            KimaScreenGround()

            switch phase {
            case .loading:
                KimaLoadingState(onRetry: retry)

            case .failed(let msg):
                KimaErrorState(message: msg, onRetry: retry)

            case .loaded:
                loaded()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
