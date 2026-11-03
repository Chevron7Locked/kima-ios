import SwiftUI

/// Brief launch splash shown during the cold-start /auth/me check. Visible for a fraction of a
/// second; keeps the "late-night listening room" mood — a faint violet glow over near-black, centered.
struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            KimaColor.base.ignoresSafeArea()

            // Faint violet top glow — the cosmos bleeding up from the cold start.
            LinearGradient(
                colors: [Color(hex: 0x160B1C).opacity(0.4), Color(hex: 0x0B0510).opacity(0.1), .clear],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: KimaSpacing.xl) {
                Spacer()

                // Logo + wordmark
                VStack(spacing: KimaSpacing.lg) {
                    KimaMark()
                        .frame(width: 64, height: 64)

                    Text("kima")
                        .font(KimaType.wordmark(32))
                        .foregroundStyle(KimaColor.textPrimary)
                        .tracking(-0.5)
                }

                Spacer()

                // Subtle activity indicator — not a loader, just "something is happening".
                ProgressView()
                    .tint(KimaColor.brand)
                    .padding(.bottom, KimaSpacing.huge)
            }
        }
    }
}

#Preview {
    LaunchSplashView()
}
