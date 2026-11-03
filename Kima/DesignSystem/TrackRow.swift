import SwiftUI

// MARK: - TrackRow

/// The one track row (web TrackRow), at least 44pt: number (or a mood dot), optional 40pt cover, title over a
/// muted line, an album column on wide screens, the caller's trailing extras, then the duration. The
/// current track tints its title (a faint wash in `highlight`); while it plays a waveform replaces
/// the number or dot, or sits on the cover. Buttons, menus, drag and swipe stay at the call site.
struct TrackRow<Trailing: View>: View {
    enum Artwork { case none, server(String?), remote(String?) }
    enum NowPlaying { case none, current, playing }

    var number: String? = nil
    /// A narrow dot column in place of the number (the library's tracks list).
    var moodColumn = false
    /// The dot's mood colour; nil leaves the column empty.
    var mood: Color? = nil
    var artwork: Artwork = .none
    let title: String
    var subtitle: String? = nil
    /// Album name for the wide-screen column; nil hides the column.
    var albumColumn: String? = nil
    var duration: String? = nil
    var nowPlaying: NowPlaying = .none
    /// The now-playing colour: the mood accent for library tracks, amber for previews.
    var highlight: Color = KimaColor.brand
    /// A track the user does not have: the row fades.
    var isMissing = false
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The number column's width, growing with the text size.
    @ScaledMetric(relativeTo: .caption) private var numberWidth: CGFloat = 28
    /// At accessibility text sizes the title and line wrap instead of cutting off.
    private var titleLines: Int { typeSize.isAccessibilitySize ? 3 : 1 }

    private var isCurrent: Bool { nowPlaying != .none }

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            if let number { numberColumn(number) }
            if moodColumn { moodDot }
            cover

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(title.lowercased())
                    .font(KimaType.captionStrong)
                    .foregroundStyle(isCurrent ? highlight : (isMissing ? KimaColor.textMuted : KimaColor.textPrimary))
                    .lineLimit(titleLines)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle.lowercased())
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                        .lineLimit(titleLines)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let albumColumn {
                Text(albumColumn.lowercased())
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            trailing()

            if let duration {
                Text(duration)
                    .font(KimaType.caption.monospacedDigit())
                    .foregroundStyle(KimaColor.textMuted)
                    .fixedSize()
            }
        }
        .padding(.vertical, KimaSpacing.sm)
        .frame(minHeight: KimaLayout.minTouchTarget)
        // The now-playing wash bleeds into the margin so the content stays on the gutter.
        .padding(.horizontal, KimaSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                .fill(isCurrent ? highlight.opacity(0.08) : .clear)
        )
        .padding(.horizontal, -KimaSpacing.sm)
        .opacity(isMissing ? 0.7 : 1)
        .contentShape(Rectangle())
    }

    // MARK: Leading

    private func numberColumn(_ number: String) -> some View {
        Group {
            if nowPlaying == .playing {
                waveform
            } else {
                Text(number)
                    .font(KimaType.caption.monospacedDigit())
                    .foregroundStyle(KimaColor.textMuted)
            }
        }
        // 28pt fits a three-digit or disc-prefixed ("2-03") number at 13pt monospaced; it scales with the text.
        .frame(width: numberWidth, alignment: .trailing)
    }

    private var moodDot: some View {
        Group {
            if nowPlaying == .playing {
                waveform
            } else if let mood {
                Circle().fill(mood).frame(width: 7, height: 7)
            }
        }
        .frame(width: 16)
        .accessibilityHidden(true)
    }

    private var waveform: some View {
        Image(systemName: "waveform")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(highlight)
            .symbolEffect(.variableColor.iterative)
    }

    @ViewBuilder private var cover: some View {
        switch artwork {
        case .none:
            EmptyView()
        case .server(let id):
            coverTile(CoverArtImage(coverId: id, size: 80, cornerRadius: KimaRadius.image))
        case .remote(let url):
            coverTile(RemoteArtworkImage(urlString: url, maxPixel: 120))
        }
    }

    private func coverTile(_ image: some View) -> some View {
        image
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                    .strokeBorder(KimaColor.hairline, lineWidth: 1)
            )
            .overlay {
                if number == nil, !moodColumn, nowPlaying == .playing {
                    waveform
                        .padding(KimaSpacing.xs)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous))
                }
            }
    }
}

extension TrackRow where Trailing == EmptyView {
    init(number: String? = nil, moodColumn: Bool = false, mood: Color? = nil, artwork: Artwork = .none,
         title: String, subtitle: String? = nil, albumColumn: String? = nil, duration: String? = nil,
         nowPlaying: NowPlaying = .none, highlight: Color = KimaColor.brand, isMissing: Bool = false) {
        self.init(number: number, moodColumn: moodColumn, mood: mood, artwork: artwork, title: title, subtitle: subtitle,
                  albumColumn: albumColumn,
                  duration: duration, nowPlaying: nowPlaying, highlight: highlight, isMissing: isMissing,
                  trailing: { EmptyView() })
    }
}
