import SwiftUI

// MARK: - PodcastPreviewView
// A show not followed yet: hero, category pills, "follow" (the page's one amber control), a quiet row that plays
// the first episode as a sample, the newest episodes with a one-line summary each, and "more like this".

struct PodcastPreviewView: View {
    let preview: PodcastPreview
    /// The Apple id the page was opened with; the sample stream is keyed on it.
    let itunesId: String
    let palette: CoverArtPalette?
    let isSubscribing: Bool
    let similar: [DiscoveryPodcast]
    let onSubscribe: () async throws -> Void
    let onOpenCategory: (Int) -> Void
    let onOpenShow: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toastCenter
    @State private var heroHeight: CGFloat = 0

    var body: some View {
        KimaTopInsetReader { topInset in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    PodcastHeroView(
                        coverUrl: preview.coverUrl,
                        title: preview.title,
                        author: preview.author,
                        // The category pills below name them; the meta line keeps the episode count.
                        genres: (preview.categories ?? []).isEmpty ? preview.genres : nil,
                        episodeCount: preview.episodeCount,
                        topSafeInset: topInset
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }

                    PodcastCategoryPills(categories: preview.categories ?? [], onTap: onOpenCategory)

                    followButton

                    if let snippet = preview.snippet {
                        sampleRow(snippet)
                    }

                    if let eps = preview.previewEpisodes, !eps.isEmpty {
                        KimaSectionHeader(title: "recent episodes")
                        // Keyed on offset: episodes in this snapshot may share a title.
                        ForEach(Array(eps.enumerated()), id: \.offset) { _, ep in
                            previewEpisodeRow(ep)
                            KimaHairline()
                                .padding(.leading, KimaSpacing.lg)
                        }
                    }

                    if !similar.isEmpty {
                        KimaSectionHeader(title: "more like this")
                        KimaRail(tileWidth: PodcastCardView.cardWidth) { width in
                            ForEach(similar) { show in
                                PodcastCardView(discovery: show, width: width) { onOpenShow(show.id) }
                            }
                        }
                    }

                    Spacer(minLength: KimaSpacing.lg)
                }
                .kimaReadableWidth()
                .frame(maxWidth: .infinity)
            }
            .kimaMiniPlayerClearance()
            .ignoresSafeArea(.container, edges: .top)
            .kimaHeroGround(heroHeight: heroHeight) {
                PodcastHeroBackdrop(coverUrl: preview.coverUrl, palette: palette)
            }
        }
    }

    // MARK: - Follow

    private var followButton: some View {
        VStack(spacing: KimaSpacing.sm) {
            KimaPrimaryButton(title: "follow", isLoading: isSubscribing, systemImage: "plus") {
                Task {
                    do {
                        try await onSubscribe()
                    } catch {
                        toastCenter.show("couldn't follow. check your connection.", style: .error)
                    }
                }
            }
            .disabled(isSubscribing || preview.feedUrl == nil)

            if preview.feedUrl == nil {
                Text("this show has no feed to follow")
                    .font(KimaType.meta)
                    .foregroundStyle(KimaColor.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.lg)
    }

    // MARK: - Sample

    /// The first episode, played in the main player without saving anything; tapping again pauses or resumes.
    private func sampleRow(_ snippet: PodcastSnippet) -> some View {
        let isCurrent = player.isPlayingSample(of: itunesId)
        let isPlaying = isCurrent && player.isPlaying
        return Button {
            if isCurrent {
                player.togglePlayPause()
            } else {
                player.playPodcastSample(snippet, of: preview, itunesId: itunesId, client: env.client)
            }
        } label: {
            HStack(spacing: KimaSpacing.md) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KimaColor.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(KimaColor.discGlass, in: Circle())
                    .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    Text("play first episode")
                        .font(KimaType.bodyStrong)
                        .foregroundStyle(KimaColor.textPrimary)
                    Text(sampleMeta(snippet))
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.bottom, KimaSpacing.md)
            .frame(minHeight: KimaLayout.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "pause first episode" : "play first episode, \(snippet.title)")
    }

    private func sampleMeta(_ snippet: PodcastSnippet) -> String {
        // Length first: a long title truncates after it.
        let length = snippet.duration > 0 ? "\(snippet.duration.lengthLabel) · " : ""
        return length + snippet.title.lowercased()
    }

    // MARK: - Preview episode row (read-only)

    private func previewEpisodeRow(_ ep: PreviewEpisode) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            Text(ep.title.lowercased())
                .font(KimaType.captionStrong)
                .foregroundStyle(KimaColor.textPrimary)
                .lineLimit(2)
            HStack(spacing: KimaSpacing.xs) {
                Text(ep.publishedAt.podcastDateDisplay)
                if ep.duration > 0 {
                    Text("·")
                    Text(ep.duration.lengthLabel).monospacedDigit()
                }
            }
            .font(KimaType.meta)
            .foregroundStyle(KimaColor.textMuted)
            if let summary = ep.description?.strippingHTML, !summary.isEmpty {
                Text(summary.lowercasedFirstSentence())
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}
