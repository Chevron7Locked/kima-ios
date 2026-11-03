import SwiftUI

// The result-section subviews used by `SearchResultSections`, split out to keep each file under the ~350-line cap.
// Internal (not private) so the dispatcher can reference them across files; all are search-specific.
// `SearchTopResultCard` has its own file.

// MARK: - Alias info banner

/// Shown when Last.fm resolves the query to a canonical artist name.
/// E.g. "led zepplein" → "Led Zeppelin". Subtle info bar, not an error.
struct AliasInfoBanner: View {
    let aliasInfo: AliasInfo

    var body: some View {
        HStack(spacing: KimaSpacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KimaColor.textMuted)
            Text("showing results for \u{201c}\(aliasInfo.canonical)\u{201d}")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm)
    }
}

// MARK: - Songs section

struct SearchSongsSection: View {
    let tracks: [Track]
    let onPlay: ([Track], Int) -> Void

    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    /// Display caps at 10 rows; absolute index into `tracks` is preserved so
    /// tapping plays from the full queue rather than a truncated slice.
    private var displayRows: [(offset: Int, element: Track)] {
        Array(tracks.prefix(10).enumerated()).map { ($0.offset, $0.element) }
    }

    var body: some View {
        KimaSectionHeader(title: "songs")
        VStack(spacing: 0) {
            ForEach(displayRows, id: \.element.id) { row in
                let track = row.element
                let isCurrent = player.currentTrack?.id == track.id

                Button { onPlay(tracks, row.offset) } label: {
                    TrackRow(artwork: .server(track.album?.coverArt), title: track.effectiveTitle,
                             subtitle: [track.artist?.name, track.album?.title].compactMap { $0 }.joined(separator: " · "),
                             duration: track.duration.durationFormatted,
                             nowPlaying: isCurrent ? (player.isPlaying ? .playing : .current) : .none,
                             highlight: env.accent.color)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    TrackQueueMenuItems(track: row.element, player: player, playlistPicker: env.playlistPicker, toast: toast)
                }
                .modifier(TrackDragModifier(track: row.element, enabled: true))
                .padding(.horizontal, KimaSpacing.lg)

                if row.offset < displayRows.count - 1 {
                    KimaHairline()
                        .padding(.horizontal, KimaSpacing.lg)
                }
            }
        }
    }
}

// MARK: - Albums section

struct SearchAlbumsSection: View {
    let albums: [Album]
    let onTap:  (Album) -> Void

    var body: some View {
        KimaSectionHeader(title: "albums")
        KimaRail(tileWidth: 148) { width in
            ForEach(albums) { album in
                KimaCoverCard(title: album.effectiveTitle, subtitle: album.artist?.name, titleLines: 2,
                              onTap: { onTap(album) }) {
                    CoverArtImage(coverId: album.coverArt ?? album.coverUrl, size: 256, cornerRadius: 0)
                }
                .frame(width: width)
            }
        }
    }
}

// MARK: - Podcasts section (library subscriptions)

struct SearchPodcastsSection: View {
    let podcasts: [SearchPodcast]
    let onTap:    (SearchPodcast) -> Void

    var body: some View {
        KimaSectionHeader(title: "podcasts")
        KimaRail(tileWidth: PodcastCardView.cardWidth) { width in
            ForEach(podcasts) { podcast in
                PodcastCardView(
                    coverId:  podcast.imageUrl,
                    title:    podcast.title,
                    author:   podcast.author ?? "",
                    subtitle: { let c = podcast.episodeCount ?? 0; return "\(c) episode\(c == 1 ? "" : "s")" }(),
                    width:    width,
                    onTap:    { onTap(podcast) }
                )
            }
        }
    }
}

// MARK: - Audiobooks section

struct SearchAudiobooksSection: View {
    let audiobooks: [SearchAudiobook]
    let onTap:      (SearchAudiobook) -> Void

    var body: some View {
        KimaSectionHeader(title: "books")
        KimaRail(tileWidth: 148) { width in
            ForEach(audiobooks) { book in
                AudiobookCardView(
                    bookId:      book.id,
                    coverId:     book.coverUrl,
                    title:       book.title,
                    author:      book.author ?? "unknown author",
                    progressPct: nil,
                    onTap:       { onTap(book) }
                )
                .frame(width: width)
            }
        }
    }
}

// MARK: - Podcast Episodes section

/// Vertical list of matching podcast episodes (library search).
/// No cover art is available on `SearchEpisode`; a mic icon serves as the leading slot.
/// Capped at 10 rows. Tapping navigates to the parent podcast via `episode.podcastId`.
struct SearchEpisodesSection: View {
    let episodes: [SearchEpisode]
    let onTap:    (SearchEpisode) -> Void

    private var displayRows: [(offset: Int, element: SearchEpisode)] {
        Array(episodes.prefix(10).enumerated()).map { ($0.offset, $0.element) }
    }

    var body: some View {
        KimaSectionHeader(title: "episodes")
        VStack(spacing: 0) {
            ForEach(displayRows, id: \.element.id) { row in
                Button { onTap(row.element) } label: {
                    HStack(spacing: KimaSpacing.md) {
                        // Leading slot — no cover art on SearchEpisode, so a hairline-ringed
                        // icon tile stands in, matching the Songs section's 40×40 rhythm.
                        ZStack {
                            RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                                .fill(KimaColor.surface)
                                .frame(width: 40, height: 40)
                                .overlay(RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous).strokeBorder(KimaColor.hairline, lineWidth: 1))
                            Image(systemName: "mic.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(KimaColor.textMuted)
                        }

                        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                            Text(row.element.title.lowercased())
                                .font(KimaType.captionStrong)
                                .foregroundStyle(KimaColor.textPrimary)
                                .lineLimit(1)

                            Text(secondaryLine(for: row.element))
                                .font(KimaType.caption)
                                .foregroundStyle(KimaColor.textMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(KimaColor.textMuted)
                    }
                    .padding(.vertical, KimaSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, KimaSpacing.lg)

                if row.offset < displayRows.count - 1 {
                    KimaHairline()
                        .padding(.horizontal, KimaSpacing.lg)
                }
            }
        }
    }

    /// "Podcast Title · 3:45" (duration via the shared `durationFormatted` helper on Double).
    /// Duration omitted when the field is nil to avoid a dangling middot.
    private func secondaryLine(for episode: SearchEpisode) -> String {
        if let dur = episode.duration {
            return "\(episode.podcastTitle.lowercased()) · \(dur.durationFormatted)"
        }
        return episode.podcastTitle.lowercased()
    }
}

// MARK: - Related Artists section (from /search/discover/similar)

/// Circular artist rail populated from Last.fm similar-artist results.
/// These are discover artists (no library ID) — tapping pushes the discovery
/// artist detail page via `onTap`.
struct SearchRelatedArtistsSection: View {
    let artists: [DiscoverResult]
    let onTap:   (DiscoverResult) -> Void

    var body: some View {
        KimaSectionHeader(title: "related artists")
        KimaRail(tileWidth: 116) { width in
            ForEach(artists) { artist in
                // Last.fm similar-artist results always carry listeners == 0, so
                // "0K listeners" would be noise — show a subtitle only when > 0.
                KimaCoverCard(title: artist.name,
                              subtitle: (artist.listeners ?? 0) > 0 ? "\(artist.listeners! / 1_000)K listeners" : nil,
                              titleLines: 2, onTap: { onTap(artist) }) {
                    CoverArtImage(coverId: artist.image, size: 256, cornerRadius: 0)
                }
                .frame(width: width)
            }
        }
    }
}
