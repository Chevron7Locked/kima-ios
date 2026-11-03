import SwiftUI

// MARK: - Skeleton pulse

/// The one loading-placeholder pulse: placeholder shapes fill with `KimaColor.surface` and
/// breathe between 0.7 and 0.35 opacity, one second each way (the web's 2s pulse).
/// Held still at the midpoint under Reduce Motion.
private struct KimaSkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 0.5 : (dim ? 0.35 : 0.7))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

extension View {
    /// Shared skeleton pulse for loading placeholders. Apply once to the placeholder group.
    func kimaSkeletonPulse() -> some View { modifier(KimaSkeletonPulse()) }
}
