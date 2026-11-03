import SwiftUI

// Subviews for the Radio screen and its Home section.

// MARK: - StationLabel

/// A station's name and line under a mood station's sleeves: name in the headline role, the small spacing step, then
/// the line in muted caption. At accessibility text sizes both get twice the lines. `lineChoices` replaces the
/// station's own line: the first that fits in `lines` is shown whole, the last is shown cut if nothing fits.
struct StationLabel: View {
    let station: RadioStation
    var lines: Int = 1
    var lineChoices: [String]? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let scale = typeSize.isAccessibilitySize ? 2 : 1
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            Text(station.name.lowercased())
                .font(KimaType.headline)
                .foregroundStyle(KimaColor.textPrimary)
                .lineLimit(scale)
                .minimumScaleFactor(0.8)
            if let choices = lineChoices, choices.count > 1 {
                // The reserved lines set the space; the choices are measured against it.
                lineText(Array(repeating: " ", count: lines * scale).joined(separator: "\n"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hidden()
                    .overlay(alignment: .topLeading) {
                        ViewThatFits(in: .vertical) {
                            ForEach(choices.dropLast(), id: \.self) { lineText($0).fixedSize(horizontal: false, vertical: true) }
                            lineText(choices[choices.count - 1]).lineLimit(lines * scale)
                        }
                    }
            } else {
                lineText(lineChoices?.first ?? station.description)
                    .lineLimit(lines * scale, reservesSpace: lines > 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineText(_ s: String) -> some View {
        Text(s.lowercased()).font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
    }
}

/// Two pulsing bars where a mood station's name and line will be.
struct StationLabelPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            Capsule().fill(KimaColor.fillQuiet).frame(width: 90, height: 12)
            Capsule().fill(KimaColor.fillQuiet).frame(width: 120, height: 9)
        }
    }
}

// MARK: - RadioHeroView

struct RadioHeroView: View {
    let stationCount: Int
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaScreenHeader(title: "library radio",
                             statValue: !isLoading && stationCount > 0 ? stationCount : nil,
                             statLabel: "stations")
            Text("stations made from your library")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
                .padding(.horizontal, KimaSpacing.lg)
        }
        // The first section header's own top space (xxl) separates the hero from the feed.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - HowItWorksPanel

/// Static explainer panel at the foot of the Radio screen.
struct HowItWorksPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            KimaKicker(title: "how it works")
            KimaHairline()

            Text(
                "stations are built from your library. " +
                "new genre and decade stations appear as you add music. " +
                "each station needs a minimum number of tracks."
            )
            .font(KimaType.caption)
            .foregroundStyle(KimaColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(4)
        }
        .padding(KimaSpacing.xl)
        .background(KimaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                .strokeBorder(KimaColor.hairline, lineWidth: 1)
        )
    }
}

// MARK: - SkeletonGrid

/// Pulsing placeholder chips for a grid of stations while they load.
struct SkeletonGrid: View {
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: KimaSpacing.sm) {
            ForEach(0 ..< 6, id: \.self) { _ in StationChipPlaceholder() }
        }
    }
}
