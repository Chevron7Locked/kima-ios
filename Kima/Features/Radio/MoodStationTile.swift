import SwiftUI

// MARK: - Station preview

/// What a mood station tile shows from the station's first songs, in play order: up to three distinct album covers
/// and the distinct artist names.
struct StationPreview: Sendable, Equatable {
    let covers: [String]
    let artists: [String]

    init(tracks: [Track]) {
        var albums = Set<String>(), covers: [String] = []
        var names = Set<String>(), artists: [String] = []
        for t in tracks {
            if covers.count < 3, let c = t.album?.coverArt, !c.isEmpty, albums.insert(t.album?.id ?? c).inserted {
                covers.append(c)
            }
            if let n = t.artist?.name, !n.isEmpty, names.insert(n.lowercased()).inserted { artists.append(n) }
        }
        self.covers = covers
        self.artists = artists
    }

    /// Artist lines from the most names to the fewest (at most three), each ending in "…" when names are left out;
    /// the label shows the first that fits, so a name is never cut.
    var artistLines: [String] {
        let shown = min(artists.count, 3)
        guard shown > 0 else { return [] }
        return (1...shown).reversed().map { k in
            artists.prefix(k).joined(separator: ", ") + (k < artists.count ? "…" : "")
        }
    }
}

// MARK: - MoodStationTile

/// A mood station as a small stack of record sleeves: its first three albums, the front cover largest and the ones
/// behind leaning out to the right, with the station's name and its artists under it. Tapping plays the station.
/// An empty station or one whose songs didn't load keeps a quiet blank sleeve and still plays.
struct MoodStationTile: View {
    let station: RadioStation
    /// Fixed width in a rail; nil fills a grid column.
    var width: CGFloat? = nil
    let onTap: () -> Void

    @Environment(AppEnvironment.self) private var env

    private var vm: RadioViewModel { env.radioViewModel }
    private var isThisLoading: Bool { vm.loadingStationID == station.id }
    private var anyLoading: Bool { vm.loadingStationID != nil }
    private var preview: LoadPhase<StationPreview> { station.filterValue.flatMap { vm.previews[$0] } ?? .loading }
    private var isEmpty: Bool { if case .loaded(let p) = preview { return p.artists.isEmpty }; return false }

    private var covers: [String] { if case .loaded(let p) = preview { return p.covers }; return [] }
    private var isWaiting: Bool { if case .loading = preview { return true }; return false }

    private var lineChoices: [String] {
        guard case .loaded(let p) = preview else { return [station.description] }
        return isEmpty ? ["no songs for this yet"] : p.artistLines
    }

    /// The fullest artist line, spoken without its "…"; the station's own line while there are none.
    private var spokenLine: String {
        guard case .loaded(let p) = preview, let line = p.artistLines.first else { return station.description }
        return line.hasSuffix("…") ? String(line.dropLast()) + " and more" : line
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                SleeveStack(covers: covers, waiting: isWaiting, starting: isThisLoading)
                    // A rail proposes no width, so a fixed-width tile sizes its stack itself; a grid cell fills.
                    .frame(width: width, height: width.map { $0 * SleeveStack.heightRatio })
                    .aspectRatio(1 / SleeveStack.heightRatio, contentMode: .fit)
                StationLabel(station: station, lines: 2, lineChoices: lineChoices)
            }
        }
        .buttonStyle(.kimaCard)
        .frame(width: width)
        .disabled(anyLoading)
        .opacity(anyLoading && !isThisLoading ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.15), value: anyLoading)
        .accessibilityLabel("\(station.name.lowercased()) radio, \(spokenLine.lowercased())")
        .accessibilityValue(isThisLoading ? "starting" : isEmpty ? "no songs for this yet" : "")
        .task(id: vm.previewGeneration) { await vm.loadPreview(station, using: env.client) }
    }
}

// MARK: - SleeveStack

/// Up to three covers as leaning sleeves, standing on the bottom edge: the first in front, the others behind it,
/// each a step smaller, darker, further right and leaning back a little more, with a hairline edge so a dark cover
/// still separates from the one in front. No covers draws one blank sleeve, pulsing while `waiting`, with `note`
/// written on it. `starting` puts a spinner on a dark disc in the middle of the front sleeve.
struct SleeveStack: View {
    let covers: [String]
    var waiting = false
    var note: String? = nil
    var starting = false

    /// Height over width: the front sleeve's height plus room for the ones behind to lean back. The third sleeve
    /// (0.11 of the width further right per step, 0.07 smaller, 3.5° more lean) stays inside this frame.
    static let heightRatio: CGFloat = 0.84

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let front = min(side * 0.76, geo.size.height)
            ZStack(alignment: .bottomLeading) {
                if covers.isEmpty {
                    BlankSleeve(side: front)
                        .overlay {
                            if let note {
                                Text(note)
                                    .font(KimaType.caption)
                                    .foregroundStyle(KimaColor.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.6)
                                    .padding(KimaSpacing.sm)
                            }
                        }
                        .modifier(PulseWhile(on: waiting))
                } else {
                    ForEach(Array(covers.enumerated().reversed()), id: \.offset) { i, cover in
                        let step = CGFloat(i)
                        CoverArtImage(coverId: cover, size: 256, cornerRadius: KimaRadius.image)
                            .frame(width: front * (1 - step * 0.07), height: front * (1 - step * 0.07))
                            .brightness(-0.08 * Double(i))
                            .overlay {
                                if i > 0 {
                                    RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                                        .strokeBorder(KimaColor.hairline, lineWidth: 1)
                                }
                            }
                            .kimaShapeShadow(cornerRadius: KimaRadius.image, opacity: 0.55, radius: 6, x: -2, y: 3)
                            .rotationEffect(.degrees(Double(i) * -3.5), anchor: .bottomLeading)
                            .offset(x: step * side * 0.11)
                    }
                }
                if starting {
                    ProgressView()
                        .tint(KimaColor.brand)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .frame(width: front, height: front)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
        .accessibilityHidden(true)
    }
}

/// An empty sleeve: a dark square with a hairline edge.
private struct BlankSleeve: View {
    let side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
            .fill(KimaColor.surface)
            .overlay(RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                .strokeBorder(KimaColor.hairline, lineWidth: 1))
            .frame(width: side, height: side)
    }
}

private struct PulseWhile: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.kimaSkeletonPulse() } else { content }
    }
}

// MARK: - Placeholders

/// Stands in for the mood stations: four pulsing blank sleeves while they load, or one "tap to retry" tile when they
/// failed.
struct MoodStationPlaceholders: View {
    var width: CGFloat? = nil
    let failed: Bool
    let onRetry: () -> Void

    var body: some View {
        if failed {
            Button(action: onRetry) { tile(label: "mood stations didn't load · tap to retry") }
                .buttonStyle(.plain)
        } else {
            ForEach(0..<4, id: \.self) { _ in tile(label: nil).kimaSkeletonPulse() }
        }
    }

    private func tile(label: String?) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            SleeveStack(covers: [], note: label)
                .frame(width: width, height: width.map { $0 * SleeveStack.heightRatio })
                .aspectRatio(1 / SleeveStack.heightRatio, contentMode: .fit)
            StationLabelPlaceholder().opacity(label == nil ? 1 : 0)
        }
        .frame(width: width)
    }
}
