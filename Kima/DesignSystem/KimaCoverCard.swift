import SwiftUI

// MARK: - KimaCoverCard

/// The one cover card for rails and grids: square art with a hairline edge, a lowercase title over one muted
/// line, and the shared spring press. With a subtitle, cards in a grid share one height. Optional: a third muted
/// line (`detail`), a corner play badge (`onPlay`, amber while `isPlaying`), a mood dot and a top-trailing
/// accessory. The caller sets the width; a card with no destination fades to half.
struct KimaCoverCard<Artwork: View, Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var titleLines: Int = 1
    /// A third muted line under the subtitle (a podcast's episode count).
    var detail: String? = nil
    /// A small mood-colour dot before the subtitle.
    var mood: Color? = nil
    var isPlaying: Bool = false
    /// Playback for this card is being fetched: the badge spins and taps are ignored.
    var isBusy: Bool = false
    var onPlay: (() -> Void)? = nil
    let onTap: () -> Void
    /// The name for the card's open target in UI tests — e.g. "mix-card". Set this from the call site; do NOT put
    /// `.accessibilityIdentifier` on the whole card: a container identifier overrides the identifiers of everything
    /// inside it, including the play badge's own "play-badge", which hides the badge from the tests that watch it spin.
    var openID: String? = nil
    @ViewBuilder let artwork: () -> Artwork
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        // One open target for the whole card; the play badge and the accessory sit over the artwork as siblings,
        // because a control inside a Button's label never receives the touch.
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // A width-bound square, so any artwork (cover, remote image, mosaic) fills it exactly.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { artwork() }
                    .clipShape(RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                            .strokeBorder(KimaColor.hairline, lineWidth: 1)
                    )
                    .kimaSleeveElevation(cornerRadius: KimaRadius.image)
                textLines
                    .padding(.top, KimaSpacing.sm)
                    .padding(.horizontal, KimaSpacing.xs)
                    .padding(.bottom, KimaSpacing.xs)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.kimaCard)
        .kimaDisabled(opacity: 0.5)
        .modifier(OpenIdentifier(id: openID))
        .overlay(alignment: .top) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if let onPlay {
                        // In a grid of two hundred covers a bare "play" says nothing about which item plays, so
                        // the badge is named after the card, busy state included.
                        CoverPlayBadge(isActive: isPlaying, isBusy: isBusy, action: onPlay)
                            .accessibilityLabel(isBusy ? "loading \(displayTitle)" : "play \(displayTitle)")
                            .padding(KimaSpacing.sm)
                    }
                }
                .overlay(alignment: .topTrailing) { accessory() }
        }
    }

    /// Title and muted lines. With a subtitle, cards in a grid share one height: a hidden copy holds the full line
    /// count when the title may wrap or the subtitle is blank, so a short title keeps the card's height while its
    /// subtitle sits right under it.
    @ViewBuilder private var textLines: some View {
        if let subtitle, titleLines > 1 || subtitle.isEmpty {
            ZStack(alignment: .topLeading) {
                lines(title: " ", subtitle: " ", detail: nil, reserve: true)
                    .hidden()
                    .accessibilityHidden(true)
                lines(title: displayTitle, subtitle: subtitle, detail: detail, reserve: false)
            }
        } else {
            lines(title: displayTitle, subtitle: subtitle, detail: detail, reserve: false)
        }
    }

    /// A blank title reads "unknown", so a card is never left without a label.
    private var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : title.lowercased()
    }

    private func lines(title: String, subtitle: String?, detail: String?, reserve: Bool) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            Text(title)
                .font(KimaType.captionStrong)
                .foregroundStyle(KimaColor.textPrimary)
                .lineLimit(titleLines, reservesSpace: reserve)
                .truncationMode(.tail)
            if let subtitle, reserve || !subtitle.isEmpty {
                HStack(spacing: KimaSpacing.xs) {
                    if let mood, !reserve { Circle().fill(mood).frame(width: 6, height: 6) }
                    mutedLine(subtitle)
                }
            }
            if let detail, !detail.isEmpty { mutedLine(detail) }
        }
    }

    private func mutedLine(_ text: String) -> some View {
        Text(text.lowercased())
            .font(KimaType.caption)
            .monospacedDigit()
            .foregroundStyle(KimaColor.textMuted)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

extension KimaCoverCard where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, titleLines: Int = 1, detail: String? = nil, mood: Color? = nil,
         isPlaying: Bool = false, isBusy: Bool = false, onPlay: (() -> Void)? = nil, onTap: @escaping () -> Void,
         openID: String? = nil,
         @ViewBuilder artwork: @escaping () -> Artwork) {
        self.init(title: title, subtitle: subtitle, titleLines: titleLines, detail: detail, mood: mood,
                  isPlaying: isPlaying, isBusy: isBusy, onPlay: onPlay, onTap: onTap, openID: openID,
                  artwork: artwork, accessory: { EmptyView() })
    }
}

/// Puts `openID` on the card's open button only.
private struct OpenIdentifier: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}
