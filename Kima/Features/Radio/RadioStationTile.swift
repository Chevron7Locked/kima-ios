import SwiftUI

// MARK: - RadioStationTile

/// A station without covers (quick start, genre, decade) as a compact button: an icon that says what kind of station
/// it is, the name, and a small play disc, on a quiet rounded ground; the whole button plays. Fixed width in the Home
/// rows; nil fills a Radio page grid column. The station that is starting shows a spinner in its disc and the others
/// dim.
struct RadioStationTile: View {
    let station: RadioStation
    /// ID of the station currently fetching tracks (nil when idle).
    let loadingStationID: String?
    var width: CGFloat? = nil
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var isThisLoading: Bool { loadingStationID == station.id }
    private var anyLoading: Bool    { loadingStationID != nil }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: KimaSpacing.sm) {
                Image(systemName: station.symbol)
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textSecondary)
                    .frame(minWidth: 20)
                Text(station.name.lowercased())
                    .font(KimaType.bodyStrong)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: KimaSpacing.xs)
                StationPlayDisc(loading: isThisLoading)
            }
            .padding(.leading, KimaSpacing.md)
            .padding(.trailing, KimaSpacing.sm)
            .padding(.vertical, KimaSpacing.sm)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil, minHeight: StationChipGround.height)
            .modifier(StationChipGround())
        }
        .buttonStyle(.kimaCard)
        .disabled(anyLoading)
        .opacity(anyLoading && !isThisLoading ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: anyLoading)
        .accessibilityLabel("\(station.name.lowercased()) radio, \(station.description.lowercased())")
        .accessibilityValue(isThisLoading ? "starting" : "")
    }
}

// MARK: - Ground

/// The chip's quiet ground: a faint fill and a hairline edge in the card radius, no accent colour.
struct StationChipGround: ViewModifier {
    /// Resting height of a chip: above the 44pt touch minimum, with room for the disc.
    static let height: CGFloat = 52

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
        content
            .background(KimaColor.fillQuiet, in: shape)
            .overlay(shape.strokeBorder(KimaColor.hairline, lineWidth: 1))
            .contentShape(shape)
    }
}

/// A pulsing empty chip, the same size as a real one, while genres and decades load.
struct StationChipPlaceholder: View {
    var width: CGFloat? = nil

    var body: some View {
        Color.clear
            .frame(width: width, height: StationChipGround.height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .modifier(StationChipGround())
            .kimaSkeletonPulse()
    }
}

// MARK: - Play disc

/// The small quiet play disc at the end of a station chip; `loading` swaps its glyph for a spinner.
struct StationPlayDisc: View {
    var loading = false
    @ScaledMetric(relativeTo: .headline) private var scaledDisc: CGFloat = 28

    /// Grows with the text size but stops at 36pt so a name in a narrow chip keeps its room.
    private var discSize: CGFloat { min(scaledDisc, 36) }

    var body: some View {
        ZStack {
            Circle()
                .fill(KimaColor.fillQuiet)
                .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
            if loading {
                ProgressView().controlSize(.small).tint(KimaColor.brand)
                    .transition(.opacity)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: discSize * 0.36, weight: .semibold))
                    .foregroundStyle(KimaColor.textPrimary)
                    .offset(x: discSize * 0.04)  // optical: centres the triangle's mass in the disc
                    .transition(.opacity)
            }
        }
        .frame(width: discSize, height: discSize)
        .animation(.easeInOut(duration: 0.15), value: loading)
        .accessibilityHidden(true)
    }
}

// MARK: - Station icon

extension RadioStation {
    /// SF Symbol that says what kind of station this is, shown on its chip.
    var symbol: String {
        switch filterType {
        case "all":       "shuffle"
        case "workout":   "figure.run"
        case "discovery": "safari"
        case "favorites": "heart"
        case "genre":     "guitars"
        case "decade":    "calendar"
        default:          "dot.radiowaves.left.and.right"
        }
    }
}
