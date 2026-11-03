import SwiftUI

/// What the bottom of the map shows. Pure, so it can be tested without a view.
enum VibeReadout {

    enum Content: Equatable {
        case none
        /// The help list.
        case help
        /// The open song path or blend panel.
        case panel
        /// The selected track's name, artist and actions.
        case track
    }

    /// Help, while open, covers whatever is there without changing it; then an open panel; then the
    /// selected track.
    static func content(helpOpen: Bool, panelOpen: Bool, hasSelection: Bool) -> Content {
        if helpOpen { return .help }
        if panelOpen { return .panel }
        return hasSelection ? .track : .none
    }

    /// Name shown for a track: lowercase, like the rest of the app.
    static func displayTitle(_ title: String) -> String { title.lowercased() }
}

/// The selected star's readout, above the mini player and left of the rail, on `VibeFadeBackdrop`:
/// cover and title, then artist · "album" · mood, then five icon-over-label actions (play, the one
/// amber; play similar; show similar; the blend's "more like" and "less like"). Reports its frame so
/// the map can draw the leader line down to its top edge.
struct VibeReadoutView: View {
    let track: VibeMapTrack
    let isPlayLoading: Bool
    let playError: String?
    let onPlay: () -> Void
    let onPlaySimilar: () -> Void
    let onSimilar: () -> Void
    let onMoreLike: () -> Void
    let onLessLike: () -> Void
    let onOpenArtist: () -> Void
    let onOpenAlbum: () -> Void
    let onFrameChange: (CGRect?) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            HStack(spacing: KimaSpacing.md) {
                CoverArtImage(coverId: track.coverUrl, size: 96, cornerRadius: KimaRadius.image,
                              accessibilityLabel: "\(track.title) artwork")
                    .frame(width: 36, height: 36)
                    .accessibilityIdentifier("vibe-tray-cover")
                Text(VibeReadout.displayTitle(track.title))
                    .font(KimaType.figure)
                    .tracking(-0.3)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(2)
                    .accessibilityIdentifier("vibe-tray-title")
            }
            // One line, the artist giving way; at the accessibility text sizes one line each.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { artistLink; albumLink; mood }
            } else {
                HStack(spacing: KimaSpacing.sm) { artistLink; dot; albumLink; mood; Spacer(minLength: 0) }
            }
            if let playError { VibeErrorLine(playError, id: "vibe-tray-error") }
            actions.padding(.top, KimaSpacing.xs)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrameChange($0) }
        .padding(.leading, KimaSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: KimaColor.base, radius: 8, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vibe-tray")
        .onDisappear { onFrameChange(nil) }
    }

    // MARK: Meta line

    private var dot: some View {
        Text("·").font(KimaType.caption).foregroundStyle(KimaColor.textMuted).accessibilityHidden(true)
    }

    /// Opens the artist; the one part of the line that gives way when it is long.
    private var artistLink: some View {
        Button(action: onOpenArtist) {
            Text(track.artist.lowercased())
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
                .lineLimit(1)
                .kimaHitTarget(growsLayout: false)
        }
        .buttonStyle(.plain)
        .layoutPriority(-1)
        .accessibilityIdentifier("vibe-tray-artist")
    }

    private var albumLink: some View {
        Button(action: onOpenAlbum) {
            HStack(spacing: KimaSpacing.xs) {
                Text("album").font(KimaType.caption)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(KimaColor.textSecondary)
            .kimaHitTarget(growsLayout: false)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("open album")
        .accessibilityIdentifier("vibe-tray-album")
    }

    private var mood: some View {
        HStack(spacing: KimaSpacing.xs) {
            Circle().fill(VibeMoodPalette.mapColor(for: track.dominantMood)).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(VibeMoodPalette.label(for: track.dominantMood))
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("vibe-tray-mood")
    }

    // MARK: Actions

    /// The five actions, equal width with a gap between, icon over a label of up to two lines. A hairline
    /// sets the two blend actions apart from the three for this track.
    private var actions: some View {
        HStack(alignment: .top, spacing: KimaSpacing.sm) {
            action("play", "play.fill", id: "vibe-tray-play", tint: KimaColor.brand, busy: isPlayLoading, onPlay)
            action("play similar", "waveform", id: "vibe-tray-play-similar", onPlaySimilar)
            action("show similar", "circle.dashed.inset.filled", id: "vibe-tray-similar", onSimilar)
            Rectangle().fill(KimaColor.hairline).frame(width: 1, height: 28).padding(.top, KimaSpacing.xs)
                .accessibilityHidden(true)
            action("more like", "plus.circle", spoken: "blend: more like", id: "vibe-tray-more", onMoreLike)
            action("less like", "minus.circle", spoken: "blend: less like", id: "vibe-tray-less", onLessLike)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func action(_ label: String, _ symbol: String, spoken: String? = nil, id: String,
                        tint: Color = KimaColor.textPrimary, busy: Bool = false,
                        _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: KimaSpacing.xs) {
                Group {
                    if busy { ProgressView().controlSize(.mini).tint(tint) }
                    else { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                }
                .frame(width: 20, height: 20)
                Text(label)
                    .font(KimaType.meta)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: KimaLayout.minTouchTarget, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.kimaCard)
        .disabled(busy)
        .accessibilityLabel(spoken ?? label)
        .accessibilityIdentifier(id)
    }
}
