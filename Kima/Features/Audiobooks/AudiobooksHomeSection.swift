import SwiftUI

/// Home rail of in-progress audiobooks (GET /api/audiobooks/continue-listening). Hidden when empty or when
/// Audiobookshelf is not set up. The parent supplies onSeeAll and onSelectBook.
struct AudiobooksHomeSection: View {
    /// Called when the "see all" header link is tapped.
    var onSeeAll: (() -> Void)? = nil
    /// Called with the audiobook id when a card is tapped.
    var onSelectBook: ((String) -> Void)? = nil

    @Environment(AppEnvironment.self) private var env
    @State private var items: [AudiobookContinueItem] = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if hasLoaded && !items.isEmpty {
                sectionContent
            }
        }
        .task { await load() }
    }

    // MARK: - Section Content

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "audiobooks", onSeeAll: onSeeAll)

            KimaRail(tileWidth: 148) { width in
                ForEach(items) { item in
                    AudiobookCardView(
                        bookId: item.id,
                        coverId: item.coverUrl,
                        title: item.title,
                        author: item.author,
                        progressPct: item.progressPct,
                        isFinished: item.isFinished
                    ) {
                        onSelectBook?(item.id)
                    }
                    .frame(width: width)
                }
            }
        }
    }

    // MARK: - Fetch

    private func load() async {
        do {
            let all = try await env.client.getContinueListeningAudiobooks()
            // Home rail shows in-progress only — finished books are noise here.
            items = all.filter { !$0.isFinished }
        } catch {
            // Silently hide the section on error — not a fatal screen failure.
        }
        hasLoaded = true
    }
}
