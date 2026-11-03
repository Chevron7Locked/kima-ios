import SwiftUI

// MARK: - AudiobookDetailView

/// Audiobook detail: cover hero, action bar, chapters, about, series. Loads
/// `GET /api/audiobooks/:id` on appear; the palette falls back to a violet gradient until ready.
struct AudiobookDetailView: View {
    let id: String

    @Environment(AppEnvironment.self) private var env
    @State private var vm = AudiobookDetailViewModel()
    @State private var heroHeight: CGFloat = 0

    var body: some View {
        ZStack {
            KimaScreenGround()
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.load(id: id, client: env.client)
            await vm.fetchPalette(server: env.server)
        }
    }

    // MARK: - Content branch

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.audiobook == nil {
            KimaLoadingState()
        } else if let book = vm.audiobook {
            bookScroll(book)
        } else if let err = vm.errorMessage {
            errorView(err)
        }
    }

    // MARK: - Book scroll

    private func bookScroll(_ book: Audiobook) -> some View {
        // The hero pads its content clear of the status bar; the page draws the cover backdrop behind it to the top edge.
        KimaTopInsetReader { topInset in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(book, topSafeInset: topInset)

                    AudiobookActionBar(book: book, vm: vm)
                        .padding(.horizontal, KimaSpacing.lg)

                    if !vm.displaySections.isEmpty {
                        LiveSectionList(
                            sections: vm.displaySections,
                            isLoaded: isThisBookLoaded(book),
                            isPlaying: isThisBookPlaying(book)
                        ) { section in
                            if isThisBookLoaded(book) {
                                env.player.seek(to: section.start)
                            } else {
                                Task { await env.player.playAudiobook(book, client: env.client, resumeAt: section.start) }
                            }
                        }
                    }

                    if let about = vm.aboutText {
                        AboutSection(text: about)
                    }

                    if let series = book.series {
                        SeriesBlock(series: series)
                    }

                    // Sparse-book fallback: a title with no chapters, description, or series
                    // would otherwise drop to a stark black void under the action bar. Give the
                    // page a closing beat — the catalog facts we do have, or a quiet note — so it
                    // always reads as finished rather than broken.
                    if vm.displaySections.isEmpty && vm.aboutText == nil && book.series == nil {
                        sparseFooter(book)
                    }

                    Spacer(minLength: KimaSpacing.lg)
                }
                .kimaReadableWidth()
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .kimaMiniPlayerClearance()
            // Let the hero backdrop reach the true top edge (under the notch); only .top so the
            // bottom mini-player / tab-bar insets stay intact.
            .ignoresSafeArea(.container, edges: .top)
            .kimaHeroGround(heroHeight: heroHeight) { heroBackdrop(book) }
        }
    }

    // MARK: - Hero

    private func hero(_ book: Audiobook, topSafeInset: CGFloat) -> some View {
        KimaDetailHero(topInset: topSafeInset) {
            CoverArtImage(coverId: book.coverUrl, size: 512, cornerRadius: KimaRadius.hero, placeholderSymbol: "book")
        } info: {
            KimaDetailHeroTitle(text: book.title)
            KimaDetailHeroByline(text: book.author)
            if let narrator = book.narrator, !narrator.isEmpty {
                Text("narrated by \(narrator.lowercased())")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .lineLimit(2)
            }
            heroMetaLine(book)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }
    }

    /// The cover blurred over the page colour with the palette gradient on top; pinned behind the hero.
    private func heroBackdrop(_ book: Audiobook) -> some View {
        ZStack {
            KimaColor.base
            KimaPreblurredCover(coverId: book.coverUrl, size: 512, radius: 28, zoom: 1.1)
            heroGradient
        }
    }

    @ViewBuilder
    private var heroGradient: some View {
        if let p = vm.palette {
            LinearGradient(stops: [
                .init(color: p.vibrant.opacity(0.35),     location: 0),
                .init(color: p.darkVibrant.opacity(0.62), location: 0.45),
                .init(color: p.darkMuted.opacity(0.92),   location: 0.75),
                .init(color: KimaColor.base,               location: 1),
            ], startPoint: .top, endPoint: .bottom)
        } else {
            // Neutral brand fallback until palette resolves
            LinearGradient(stops: [
                .init(color: KimaColor.ambient.opacity(0.14), location: 0),
                .init(color: KimaColor.base.opacity(0.85),  location: 0.68),
                .init(color: KimaColor.base,                location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    /// Length first so it never truncates, then year and genre.
    private func heroMetaLine(_ book: Audiobook) -> some View {
        KimaDetailHeroMeta(parts: [
            book.duration > 0 ? book.duration.lengthLabel : nil,
            book.publishedYear,
            book.genres?.first?.lowercased(),
        ].compactMap { $0 })
    }

    // MARK: - Sparse-book footer

    private struct DetailRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// Catalog facts NOT already surfaced in the hero meta line (which shows length · year ·
    /// genre). Only non-empty fields become rows, so a metadata-poor title yields none.
    private func detailRows(_ book: Audiobook) -> [DetailRow] {
        var rows: [DetailRow] = []
        if let publisher = book.publisher, !publisher.isEmpty { rows.append(.init(label: "publisher", value: publisher)) }
        if let genres = book.genres, !genres.isEmpty { rows.append(.init(label: "genre", value: genres.joined(separator: ", "))) }
        if let language = book.language, !language.isEmpty { rows.append(.init(label: "language", value: language.lowercased())) }
        // A single file isn't worth a row; multiple files (without chapter markers) is useful context.
        if let n = book.trackCount, n > 1 { rows.append(.init(label: "files", value: "\(n)")) }
        return rows
    }

    /// Non-apologetic teaching line for a chapterless title — explains *why* there's no list.
    private func sparseNote(_ book: Audiobook) -> String {
        book.duration > 0
            ? "no chapters (\(book.duration.lengthLabel) total)"
            : "no chapters."
    }

    @ViewBuilder
    private func sparseFooter(_ book: Audiobook) -> some View {
        let rows = detailRows(book)
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "details")

            if rows.isEmpty {
                Text(sparseNote(book))
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, KimaSpacing.lg)
            } else {
                VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                    ForEach(rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.md) {
                            Text(row.label)
                                .font(KimaType.caption)
                                .foregroundStyle(KimaColor.textMuted)
                                .frame(width: 92, alignment: .leading)
                            Text(row.value)
                                .font(KimaType.body)
                                .foregroundStyle(KimaColor.textSecondary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, KimaSpacing.lg)
            }
        }
    }

    // MARK: - Playback state (drives the chapter-list highlight)

    /// True when `book` is the one currently loaded in the player (playing or paused).
    private func isThisBookLoaded(_ book: Audiobook) -> Bool { env.player.isAudiobookLoaded(book.id) }

    private func isThisBookPlaying(_ book: Audiobook) -> Bool {
        isThisBookLoaded(book) && env.player.isPlaying
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        KimaErrorState(message: message) { Task { await vm.load(id: id, client: env.client) } }
    }
}

/// The chapter list with the current chapter marked. It reads the playback position itself, so the position's
/// once-a-second updates rebuild this list only, not the page around it.
private struct LiveSectionList: View {
    let sections: [AudiobookSection]
    /// This book is the one in the player.
    let isLoaded: Bool
    let isPlaying: Bool
    let onSelect: (AudiobookSection) -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        SectionListView(sections: sections, currentIndex: currentIndex, isPlaying: isPlaying, onSelect: onSelect)
    }

    /// Server (1-based) `index` of the chapter containing the playback position, or nil when this book isn't loaded.
    /// Sections are in book order (ascending `start`); the last one whose `start` has been reached is current.
    private var currentIndex: Int? {
        guard isLoaded else { return nil }
        let time = env.player.currentTime
        return sections.last { $0.start <= time }?.index
    }
}
