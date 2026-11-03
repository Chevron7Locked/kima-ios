import SwiftUI

// MARK: - Design Lab (internal)

/// Internal prototype gallery — DEBUG-only, reached from Settings. The home for living
/// "Filament"-era visual experiments (logos, adaptive accents, transitions). Not shipped.
struct DesignLabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KimaSpacing.huge) {
                LivingLogosDemo()
                FilamentAccentDemo()
            }
            .padding(KimaSpacing.lg)
            .kimaReadableWidth()
            .frame(maxWidth: .infinity)
        }
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
        .background(KimaScreenGround())
        .navigationTitle("design lab")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Living logos

private struct LivingLogosDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.lg) {
            Text("logo styles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KimaColor.textMuted)

            HStack(alignment: .top, spacing: KimaSpacing.md) {
                cell("angular", "rainbow spin") { KimaMark(style: .holographic) }
                cell("linear",  "color flow")   { KimaMark(style: .drift) }
                cell("shiny",   "chrome shine")      { KimaMark(style: .shiny) }
            }

            // A big hero of the current favourite so the motion is easy to read.
            Text("hero — angular @ 130pt")
                .font(.system(size: 11))
                .foregroundStyle(KimaColor.textMuted)
                .padding(.top, KimaSpacing.md)
            KimaMark(style: .holographic)
                .frame(width: 130, height: 130)
                .frame(maxWidth: .infinity)
        }
    }

    private func cell<V: View>(_ label: String, _ sub: String,
                               @ViewBuilder _ mark: () -> V) -> some View {
        VStack(spacing: KimaSpacing.sm) {
            mark().frame(width: 84, height: 84)
            Text(label).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(KimaColor.textPrimary)
            Text(sub).font(.system(size: 9))
                .foregroundStyle(KimaColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Filament Accent

/// DEBUG preview of the player colour: swatches at gradient shares 0, 0.25, 0.5, 0.75, 1 plus brand.
private struct FilamentAccentDemo: View {

    private let shares: [Double] = [0, 0.25, 0.5, 0.75, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.lg) {
            Text("player colours")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KimaColor.textMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KimaSpacing.md) {
                    ForEach(shares, id: \.self) { share in
                        let accent = FilamentAccent(colour: share)
                        swatchView(color: accent.color, bright: accent.bright, deep: accent.deep,
                                   label: String(format: "%.2f", share))
                    }
                    swatchView(color: FilamentAccent.brand.color,
                               bright: FilamentAccent.brand.bright,
                               deep: FilamentAccent.brand.deep,
                               label: "brand")
                }
            }
        }
    }

    private func swatchView(color: Color, bright: Color, deep: Color, label: String) -> some View {
        VStack(spacing: KimaSpacing.xs) {
            VStack(spacing: KimaSpacing.xs) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(bright)
                    .frame(width: 56, height: 14)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color)
                    .frame(width: 56, height: 40)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(deep)
                    .frame(width: 56, height: 14)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(KimaColor.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 64)
    }
}
