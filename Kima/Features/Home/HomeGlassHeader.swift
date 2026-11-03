import SwiftUI

// MARK: - HomeGlassHeader

/// Floating glass wordmark chrome pinned top-leading over the Home feed (glass is chrome, never content). The feed
/// scrolls under it and refracts through the glass on iOS 26 (`.ultraThinMaterial` fallback). Sits at the same
/// height as the top-trailing `ActivityBell`. Carries the KimaMark, wordmark and date.
struct HomeGlassHeader: View {
    /// A page is open over Home, so the mark's animation holds still.
    var covered = false

    private var showDate: String {
        Formatters.homeShowDate.string(from: Date()).lowercased()
    }

    var body: some View {
        // Flexible-ideal (maxWidth: .infinity), NEVER a GeometryReader: inside a NavigationStack
        // (which proposes .unspecified) any content-sized width resolves against the inflated
        // content ideal and parks the pill off-screen. Infinity ideal ⇒ laid out at the window.
        VStack(spacing: 0) {
                HStack(spacing: 0) {
                    HStack(spacing: KimaSpacing.xs) {
                        KimaMark(paused: covered)
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                        Text("kima")
                            .font(KimaType.wordmark(12))
                            .foregroundStyle(KimaColor.textPrimary)
                            .tracking(2.0)
                        Text(showDate)
                            .font(KimaType.meta)
                            .foregroundStyle(KimaColor.textMuted)
                    }
                    .padding(.horizontal, KimaSpacing.md)
                    // Same height as the bell disc in the opposite corner.
                    .frame(height: KimaLayout.cornerDiscSize)
                    .kimaGlassChrome(in: Capsule())
                    .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("kima, \(showDate)")

                    Spacer(minLength: 0)
                }
                .padding(.leading, KimaSpacing.lg)
                Spacer(minLength: 0)
            }
        .padding(.top, KimaSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}
