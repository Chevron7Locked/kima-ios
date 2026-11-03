import SwiftUI

/// Persistent pill that slides in from the top whenever the device has no viable network
/// path. Fills its container and pins to the top, so it centres over whatever column hosts it
/// (the whole window on iPhone, the content column on iPad). Passes all taps through.
struct OfflineBannerPill: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            if !env.network.isOnline {
                HStack(spacing: KimaSpacing.xs) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(KimaColor.caution)
                        .accessibilityHidden(true)
                    Text("no internet connection")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.caution.opacity(0.9))
                }
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.vertical, KimaSpacing.sm)
                .background(
                    Capsule()
                        .fill(KimaColor.surfaceRaised)
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(KimaColor.caution.opacity(0.22), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, KimaSpacing.sm)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: env.network.isOnline)
        .allowsHitTesting(false)
    }
}
