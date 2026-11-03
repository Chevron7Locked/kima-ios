import SwiftUI

// MARK: - Date helper (file-private)
// Episode.publishedAt is an ISO-8601 String (not Date). Parse and format for display.

extension String {
    /// Parse an ISO-8601 episode publishedAt string → lowercase display ("mar 12" or "jan 5, 2024").
    var podcastDateDisplay: String {
        guard let date = Formatters.parseISO8601(self) else { return self }
        return Formatters.displayDate(date)
    }
}

// MARK: - PodcastCardView

/// Podcast card: the shared cover card with the title over the author and an optional third line (the episode
/// count). Two inits: one from individual fields, one from a `DiscoveryPodcast`.
struct PodcastCardView: View {
    let coverId: String?
    let title: String
    let author: String
    let subtitle: String?
    let onTap: () -> Void

    /// Fixed width for horizontal rails. Pass `width: nil` inside a grid to fill the column instead.
    static let cardWidth: CGFloat = 148
    var width: CGFloat? = PodcastCardView.cardWidth

    // Base init — used when caller already has individual fields.
    init(coverId: String?, title: String, author: String, subtitle: String?, width: CGFloat? = PodcastCardView.cardWidth, onTap: @escaping () -> Void) {
        self.width    = width
        self.coverId  = coverId
        self.title    = title
        self.author   = author
        self.subtitle = subtitle
        self.onTap    = onTap
    }

    /// Discovery / chart card. Chart answers carry no episode count (0), so the third line shows only a real count.
    init(discovery: DiscoveryPodcast, width: CGFloat? = PodcastCardView.cardWidth,
         onTap: @escaping () -> Void) {
        self.width = width
        coverId   = discovery.coverUrl
        title     = discovery.title
        author    = discovery.author
        subtitle  = discovery.episodeCount.flatMap { $0 > 0 ? "\($0) episode\($0 == 1 ? "" : "s")" : nil }
        self.onTap = onTap
    }

    var body: some View {
        KimaCoverCard(title: title, subtitle: author, titleLines: 2, detail: subtitle, onTap: onTap) {
            CoverArtImage(coverId: coverId, size: 256, cornerRadius: 0, placeholderSymbol: "mic")
        }
        .frame(width: width)
    }
}

// MARK: - EpisodeRowView

/// Podcast episode row: play/pause icon, title, date · length · progress, and a trailing "•••" menu
/// with mark as played / remove progress (the same actions also sit on a long press).
struct EpisodeRowView: View {
    let episode: Episode
    let isPlaying: Bool
    let onPlay: () -> Void
    let onMarkComplete: () -> Void
    let onDeleteProgress: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            playButton
            if hasActions { actionsMenu }
        }
    }

    private var isFinished: Bool { episode.progress?.isFinished == true }
    private var hasActions: Bool { !isFinished || episode.progress != nil }

    /// The episode's actions, shared by the "•••" menu and the long press.
    @ViewBuilder
    private var actions: some View {
        if !isFinished {
            Button("mark as played", systemImage: "checkmark.circle") { onMarkComplete() }
        }
        if episode.progress != nil {
            Button("remove progress", systemImage: "arrow.counterclockwise", role: .destructive) {
                onDeleteProgress()
            }
        }
    }

    private var actionsMenu: some View {
        Menu { actions } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KimaColor.textMuted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.top, KimaSpacing.md)
        .accessibilityLabel("episode actions")
    }

    /// The whole row plays: the title and meta are what people tap first.
    private var playButton: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: KimaSpacing.md) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(isPlaying ? KimaColor.brand : KimaColor.textPrimary)
                    .padding(.top, 2)  // optical: sits the icon on the first text line

                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    Text(episode.title.lowercased())
                        .font(KimaType.captionStrong)
                        .foregroundStyle(
                            episode.progress?.isFinished == true
                                ? KimaColor.textMuted : KimaColor.textPrimary
                        )
                        .lineLimit(2)

                    HStack(spacing: KimaSpacing.xs) {
                        Text(episode.publishedAt.podcastDateDisplay)
                        Text("·")
                        Text(episode.duration.lengthLabel).monospacedDigit()
                        if let p = episode.progress, !p.isFinished, p.currentTime > 0 {
                            Text("·")
                            Text("\(Int(p.progress))%").monospacedDigit()
                        }
                        if episode.progress?.isFinished == true {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(KimaColor.textMuted)

                    if let p = episode.progress, !p.isFinished, p.currentTime > 0 {
                        KimaProgressBar(fraction: p.progress / 100)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, KimaSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("play episode \(episode.title)")
        .contextMenu { actions }
    }
}
