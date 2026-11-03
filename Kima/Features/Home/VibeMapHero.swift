import SwiftUI

// MARK: - VibeMapHero

/// Home-screen entry point for the immersive Vibe Map — THE hero of the Home feed.
///
/// Quiet entry card: flat panel, soft violet bleed, a faint twinkling star scatter, hairline.
/// Tapping presents VibeMapView as a `.fullScreenCover` (wired in HomeView).
struct VibeMapHero: View {
    let onTap: () -> Void

    private let heroHeight: CGFloat = 164
    private let cornerRadius: CGFloat = KimaRadius.card

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                ambientField
                content
            }
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(KimaColor.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, KimaSpacing.lg)
        // Headerless section: the standard between-section gap above it.
        .padding(.top, KimaSpacing.xxl)
    }

    // MARK: - Layers

    /// A night sky: true dark ink with a barely-there violet glow in the corner, under the star field. Static
    /// lighting: this is the doorway, not a live read of the map inside.
    private var ambientField: some View {
        ZStack {
            KimaColor.vibeInk

            RadialGradient(
                colors: [KimaColor.ambient.opacity(0.06), Color.clear],
                center: UnitPoint(x: 0.82, y: 0.12),
                startRadius: 4, endRadius: 200
            )

            VibeHeroStarField()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            Text("vibe map")
                .font(KimaType.section)
                .foregroundStyle(KimaColor.textPrimary)

            HStack(alignment: .lastTextBaseline, spacing: KimaSpacing.md) {
                Text("browse your library by sound")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)

                Spacer(minLength: KimaSpacing.sm)

                HStack(spacing: KimaSpacing.xs) {
                    Text("open")
                        .font(KimaType.caption)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(KimaColor.textSecondary)
            }
        }
        .padding(KimaSpacing.lg)
    }
}
