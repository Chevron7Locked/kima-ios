import SwiftUI

// MARK: - AudiobookSeriesView

/// Series detail: hero (first book's cover, series name, author, total length), one "continue series"
/// button that plays the first unfinished book, and the ordered book list. Loads
/// `GET /api/audiobooks/series/:name`. A row opens the book's page; its play badge plays it.
struct AudiobookSeriesView: View {
    let name: String

    @Environment(AppEnvironment.self) private var env

    @State private var books:        [Audiobook]      = []
    @State private var isLoading  = false
    @State private var errorMessage: String?           = nil
    @State private var palette:      CoverArtPalette? = nil
    @State private var heroHeight:   CGFloat          = 0

    // MARK: Derived

    private var firstBook: Audiobook?  { books.first }
    private var totalDuration: Double  { books.reduce(0) { $0 + $1.duration } }
    private var sharedAuthor: String   { firstBook?.author ?? "" }
    /// Genre tags for the hero meta line. Sourced from the first book —
    /// series entries share genres in practice, and the hero only has room for a couple.
    private var sharedGenres: [String]  { Array((firstBook?.genres ?? []).prefix(2)) }
    /// The book "continue series" plays: the first one not finished.
    private var nextBook: Audiobook?    { books.first { $0.progress?.isFinished != true } }
    private var seriesStarted: Bool     { books.contains { ($0.progress?.progress ?? 0) > 0 || $0.progress?.isFinished == true } }

    // MARK: Body

    var body: some View {
        ZStack {
            KimaScreenGround()
            mainContent
        }
        // System back button in a transparent bar, like the other hero detail screens.
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBooks()
            if let coverId = firstBook?.coverUrl {
                palette = await CoverArtColor.palette(coverId: coverId, server: env.server)
            }
        }
    }

    // MARK: - Content branch

    @ViewBuilder
    private var mainContent: some View {
        if isLoading && books.isEmpty {
            KimaLoadingState()
        } else if let err = errorMessage {
            errorView(err)
        } else {
            KimaTopInsetReader { topInset in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        seriesHero(topSafeInset: topInset)
                        continueButton
                        booksSection
                        Spacer(minLength: KimaSpacing.lg)
                    }
                    .kimaReadableWidth()
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .kimaMiniPlayerClearance()
                .ignoresSafeArea(.container, edges: .top)
                .kimaHeroGround(heroHeight: heroHeight) { heroBackdrop }
            }
        }
    }

    // MARK: - Hero

    private func seriesHero(topSafeInset: CGFloat) -> some View {
        KimaDetailHero(topInset: topSafeInset) {
            CoverArtImage(coverId: firstBook?.coverUrl, size: 512, cornerRadius: KimaRadius.hero, placeholderSymbol: "books.vertical")
        } info: {
            KimaDetailHeroTitle(text: name)

            if !sharedAuthor.isEmpty {
                KimaDetailHeroByline(text: sharedAuthor)
            }

            KimaDetailHeroMeta(parts: [
                "\(books.count) book\(books.count == 1 ? "" : "s")",
                totalDuration > 0 ? totalDuration.lengthLabel : nil,
                sharedGenres.isEmpty ? nil : sharedGenres.joined(separator: ", ").lowercased(),
            ].compactMap { $0 })
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }
    }

    /// The first book's cover blurred over the page colour with the palette gradient on top; pinned behind the hero.
    private var heroBackdrop: some View {
        ZStack {
            KimaColor.base
            if let first = firstBook {
                KimaPreblurredCover(coverId: first.coverUrl, size: 512, radius: 28, zoom: 1.1)
            }
            heroGradient
        }
    }

    @ViewBuilder
    private var heroGradient: some View {
        if let p = palette {
            LinearGradient(stops: [
                .init(color: p.vibrant.opacity(0.30),     location: 0),
                .init(color: p.darkVibrant.opacity(0.60), location: 0.5),
                .init(color: KimaColor.base,               location: 1),
            ], startPoint: .top, endPoint: .bottom)
        } else {
            LinearGradient(stops: [
                .init(color: KimaColor.ambient.opacity(0.15), location: 0),
                .init(color: KimaColor.base,                location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: - Continue series

    @ViewBuilder
    private var continueButton: some View {
        if let next = nextBook {
            Button {
                playOrToggle(next)
            } label: {
                Label(seriesStarted ? "continue series" : "play series", systemImage: "play.fill")
                    .font(KimaType.headline)
                    .foregroundStyle(KimaColor.onBrand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, KimaSpacing.md)
                    .background(Capsule().fill(KimaColor.brand))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.bottom, KimaSpacing.md)
            .accessibilityLabel("\(seriesStarted ? "continue series" : "play series"): \(next.title)")
        }
    }

    /// Plays `book` from its saved place, or pauses / resumes it when it is already loaded.
    private func playOrToggle(_ book: Audiobook) {
        if env.player.isAudiobookLoaded(book.id) {
            env.player.isPlaying ? env.player.pause() : env.player.resume()
        } else {
            Task { await env.player.playAudiobook(book, client: env.client) }
        }
    }

    // MARK: - Books section

    private var booksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "books")
            ForEach(Array(books.enumerated()), id: \.element.id) { idx, book in
                SeriesBookRow(book: book, sequenceNumber: idx + 1) { playOrToggle(book) }
                KimaHairline()
                    .padding(.horizontal, KimaSpacing.lg)
            }
        }
    }

    // MARK: - Fetch

    private func loadBooks() async {
        guard !isLoading else { return }
        isLoading    = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            books = try await env.client.getAudiobooksBySeries(seriesName: name)
        } catch {
            guard !Task.isCancelled, books.isEmpty else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Error view

    private func errorView(_ message: String) -> some View {
        KimaErrorState(message: message) { Task { await loadBooks() } }
    }
}
