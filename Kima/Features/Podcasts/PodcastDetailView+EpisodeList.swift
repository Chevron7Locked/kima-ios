import SwiftUI

// MARK: - PodcastDetailView · episode list (paging + footer)
//
// Split out of PodcastDetailView.swift; the accessors used here are internal on purpose for this extension.
// The header carries the episode count, filter chips sit under it, and quiet season dividers break the list.

extension PodcastDetailView {
    // MARK: - Episode list section

    @ViewBuilder
    func episodeListSection(podcast: Podcast, episodes: [Episode], playingId: String?) -> some View {
        let total = vm.episodeTotal ?? episodes.count
        KimaSectionHeader(title: "episodes \(total)") {
            Picker("sort", selection: $vm.episodeSort) {
                ForEach(PodcastEpisodeSort.allCases, id: \.self) { sort in
                    Text(sort.label).tag(sort)
                }
            }
            .pickerStyle(.menu)
            .tint(KimaColor.textMuted)
        }

        filterChips()
            .padding(.bottom, KimaSpacing.xs)

        // Rows come pre-grouped from the VM (one linear pass: filter + season runs).
        let rows = vm.displayRows(from: episodes, filter: episodeFilter)
        if episodes.isEmpty && vm.isLoadingOldestPage {
            ProgressView()
                .tint(KimaColor.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, KimaSpacing.xl)
        }
        LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.episode.id) { index, row in
                if let bar = row.seasonHeader {
                    seasonBar(bar)
                }
                EpisodeRowView(
                    episode: row.episode,
                    isPlaying: row.episode.id == playingId,
                    onPlay: {
                        playOrToggle(row.episode, podcast: podcast, queue: episodes)
                    },
                    onMarkComplete: { Task { await vm.markEpisodeComplete(episode: row.episode, client: env.client) } },
                    onDeleteProgress: { Task { await vm.deleteEpisodeProgress(episode: row.episode, client: env.client) } }
                )
                .padding(.horizontal, KimaSpacing.lg)
                KimaHairline()
                    .padding(.leading, KimaSpacing.lg + 36 + KimaSpacing.md)

                // Infinite scroll: when the 5th-from-end VISIBLE row appears, fetch the
                // next page in the background (VM serializes; stops at reachedEnd). Trigger is
                // on the filtered view; if a filter hides the tail, "load more" stays manual.
                if index == rows.count - 5 {
                    Color.clear.frame(height: 1)
                        .task {
                            await vm.loadNextPage(client: env.client)
                            // Keep the player's auto-advance snapshot in step with the
                            // freshly grown accumulator (see playOrToggle's note).
                            player.updatePodcastQueue(
                                podcastId: podcast.id,
                                episodes: vm.sortedEpisodes()
                            )
                        }
                }
            }

            // Load More / "all N episodes loaded" footer.
            if vm.canLoadMore {
                Button {
                    Task {
                        await vm.loadNextPage(client: env.client)
                        player.updatePodcastQueue(
                            podcastId: podcast.id,
                            episodes: vm.sortedEpisodes()
                        )
                    }
                } label: {
                    Text("load more episodes")
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, KimaSpacing.lg)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("load more episodes")
            } else if let total = vm.episodeTotal, vm.allLoaded, episodes.count > 50 {
                Text("all \(total) episode\(total == 1 ? "" : "s") loaded")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, KimaSpacing.lg)
            }
        }
    }

    // MARK: - Filter chips

    /// Progress-state chips on their own line under the section header. No counts: the list is
    /// paged, so a count of the loaded pages would disagree with the header's server total.
    private func filterChips() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KimaSpacing.sm) {
                ForEach(PodcastEpisodeFilter.allCases, id: \.self) { f in
                    Button {
                        episodeFilter = f
                    } label: {
                        Text(f.label)
                            .font(KimaType.caption)
                            .foregroundStyle(episodeFilter == f ? KimaColor.brand : KimaColor.textMuted)
                            .padding(.horizontal, KimaSpacing.md)
                            .padding(.vertical, KimaSpacing.sm)
                            .background(
                                Capsule().fill(episodeFilter == f ? KimaColor.brand.opacity(0.14) : Color.clear)
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    episodeFilter == f ? KimaColor.brand.opacity(0.55) : KimaColor.hairline,
                                    lineWidth: 1
                                )
                            )
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("show \(f.label) episodes")
                }
            }
            .padding(.horizontal, KimaSpacing.lg)
        }
    }

    // MARK: - Season divider

    /// Quiet divider bar for a season run, e.g. "season 4 · 19". Muted, small, tracked —
    /// the web list's section motif; no box, no rule, just a faint lifted band.
    private func seasonBar(_ label: String) -> some View {
        Text(label)
            .font(KimaType.meta)
            .tracking(0.8)
            .foregroundStyle(KimaColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.vertical, KimaSpacing.sm)
            .background(Color.white.opacity(0.03))
    }

}
