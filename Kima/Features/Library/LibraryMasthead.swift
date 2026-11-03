import SwiftUI

// MARK: - LibraryMasthead

/// The library's masthead: the title in display type, one line on how much of the library has been played,
/// and a thin band split by each mood's share of it in the vibe map's colours.
struct LibraryMasthead: View {
    /// The stats line; nil until it loads (or on a server without stats), when `fallback` shows instead.
    let heardLine: String?
    /// The active tab's count, e.g. "315 artists".
    let fallback: String
    let moods: [LibraryMoods.Share]

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            Text("library")
                .font(KimaType.pageTitle)
                .foregroundStyle(KimaColor.textPrimary)
                .tracking(-0.4)
                .lineLimit(1)

            Text(heardLine ?? fallback)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.25), value: heardLine)

            moodBand
                .padding(.top, KimaSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.md)
        .padding(.bottom, KimaSpacing.lg)
    }

    /// One 4pt bar, each mood's stretch as wide as its share; a faint track until the vibe map loads.
    private var moodBand: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(moods) { share in
                    Rectangle()
                        .fill(VibeMoodPalette.mapColor(for: share.key))
                        .frame(width: geo.size.width * share.fraction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KimaColor.fillQuiet)
            .clipShape(Capsule())
            .animation(.easeOut(duration: 0.4), value: moods)
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("moods: " + moods.map {
            "\(VibeMoodPalette.label(for: $0.key)) \(Int(($0.fraction * 100).rounded()))%"
        }.joined(separator: ", "))
        .accessibilityHidden(moods.isEmpty)
    }
}
