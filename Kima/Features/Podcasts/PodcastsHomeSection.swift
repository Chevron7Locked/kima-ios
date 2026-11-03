import SwiftUI

/// Home rail of top podcasts (getPodcastChart(category: nil, limit: 12)); hidden when the list is empty. Loads on
/// first appearance; a failed load retries on the next one.
struct PodcastsHomeSection: View {
    var onSeeAll: (() -> Void)? = nil
    var onPodcastTap: ((DiscoveryPodcast) -> Void)? = nil

    @Environment(AppEnvironment.self) private var env
    @State private var podcasts: [DiscoveryPodcast] = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if !podcasts.isEmpty {
                VStack(spacing: 0) {
                    KimaSectionHeader(
                        title: "popular podcasts",
                        onSeeAll: onSeeAll
                    )
                    KimaRail(tileWidth: PodcastCardView.cardWidth) { width in
                        ForEach(podcasts) { podcast in
                            PodcastCardView(discovery: podcast, width: width) {
                                onPodcastTap?(podcast)
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Fetch

    private func load() async {
        guard !hasLoaded else { return }
        do {
            podcasts = try await env.client.getPodcastChart(category: nil, limit: 12)
            hasLoaded = true
        } catch {
            // Silently hide the section on error — the next appearance retries.
        }
    }
}
