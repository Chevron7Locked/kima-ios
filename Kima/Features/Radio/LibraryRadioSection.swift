import SwiftUI

// MARK: - LibraryRadioSection

/// Home section for Library Radio. Uses the shared `env.radioViewModel` so Home to Radio does not refetch
/// genres and decades. Home truncation (top 6 genres, top 4 decades) is applied here;
/// RadioView reads the full lists from the same view model.
struct LibraryRadioSection: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self)    private var toastCenter
    @Environment(PlaybackController.self) private var player
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Width of the regular-width chip grid, measured.
    @State private var gridWidth: CGFloat = 0

    /// The server has sound analysis (workout and mood stations); unknown counts as yes until it answers.
    private var moodsAvailable: Bool { player.vibeEmbeddingsAvailable != false }

    /// Width of a mood station's sleeve stack.
    static let tileWidth: CGFloat = 148
    /// Width of a station chip; every chip in the rows is the same width.
    static let chipWidth: CGFloat = 172

    /// Optional closure invoked when the user taps "SEE ALL" in the section header.
    /// Pass nil to hide the see-all button (not recommended; always wire to RadioView).
    var onSeeAll: (() -> Void)? = nil

    // MARK: - Derived station list (home-mode caps applied here)

    /// Mood tiles (or their placeholders) are in the rail.
    private var showsMoodTiles: Bool {
        guard moodsAvailable else { return false }
        if case .loaded(let moods) = env.radioViewModel.moodsPhase { return !moods.isEmpty }
        return true
    }

    private var quickStations: [RadioStation] {
        env.radioViewModel.quickStations(moodsAvailable: moodsAvailable)
    }

    private var stations: [RadioStation] {
        let vm = env.radioViewModel
        var result = quickStations
        // Cap at top-6 genres / top-4 decades for the home rail.
        // The shared VM fetches the full lists so RadioView sees everything; only this
        // render site applies the cap.
        if case .loaded(let genres)  = vm.genresPhase  { result += genres.prefix(6) }
        if case .loaded(let decades) = vm.decadesPhase { result += decades.prefix(4) }
        return result
    }

    // MARK: - Body

    var body: some View {
        Group {
            // Header
            KimaSectionHeader(
                title: "library radio",
                onSeeAll: onSeeAll
            )

            // The quick, genre and decade stations as compact chips, then the mood stations as small stacks of their
            // first albums. The chips sit a small step apart and the stacks a section's gap below them, so each reads
            // as its own group.
            if sizeClass == .regular { chipGrid } else { chipRows }

            if showsMoodTiles {
                KimaRail(tileWidth: Self.tileWidth) { width in moodTiles(width: width) }
                    .padding(.top, KimaSpacing.xxl)
            }
        }
        .task {
            // loadIfNeeded is a no-op if RadioView (or a prior Home appear) already started the fetch.
            await env.radioViewModel.loadIfNeeded(using: env.client)
        }
        .task { await player.checkVibeAvailability(client: env.client) }
    }

    /// Compact width: two rows of chips that scroll together.
    private var chipRows: some View {
        KimaRail(spacing: KimaSpacing.sm) {
            ForEach(chipColumns, id: \.[0].id) { column in
                VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                    ForEach(column) { station in chip(station) }
                }
            }

            // Placeholder chips while genres/decades are still loading, as many columns as the capped rows fill.
            // Their own string ids keep them apart from the real columns, which are keyed by station id.
            if case .loading = env.radioViewModel.genresPhase {
                ForEach((0 ..< 5).map { "placeholder-\($0)" }, id: \.self) { _ in
                    VStack(spacing: KimaSpacing.sm) {
                        StationChipPlaceholder(width: Self.chipWidth)
                        StationChipPlaceholder(width: Self.chipWidth)
                    }
                }
            }
        }
    }

    /// Regular width: two full rows of chips on the same columns as the mood stacks below; "see all" has the rest.
    private var chipGrid: some View {
        let count = KimaLayout.railFit(width: gridWidth > 0 ? gridWidth : env.viewportWidth).count
        let slots = count * 2
        let shown = Array(stations.prefix(slots))
        var placeholders = 0
        if case .loading = env.radioViewModel.genresPhase { placeholders = slots - shown.count }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: KimaLayout.railGap), count: count),
                         alignment: .leading, spacing: KimaSpacing.sm) {
            ForEach(shown) { station in chip(station, width: nil) }
            ForEach((0 ..< placeholders).map { "placeholder-\($0)" }, id: \.self) { _ in StationChipPlaceholder() }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    @ViewBuilder
    private func moodTiles(width: CGFloat) -> some View {
        let vm = env.radioViewModel
        switch vm.moodsPhase {
        case .loading:
            MoodStationPlaceholders(width: width, failed: false) {}
        case .failed:
            MoodStationPlaceholders(width: width, failed: true) {
                Task { await vm.retryMoods(using: env.client) }
            }
        case .loaded(let moods):
            ForEach(moods) { station in
                MoodStationTile(station: station, width: width) { play(station) }
            }
        }
    }

    /// The chips in columns of two, filled top to bottom, so the two rows scroll as one.
    private var chipColumns: [[RadioStation]] {
        stride(from: 0, to: stations.count, by: 2).map { Array(stations[$0 ..< min($0 + 2, stations.count)]) }
    }

    private func chip(_ station: RadioStation, width: CGFloat? = Self.chipWidth) -> some View {
        RadioStationTile(station: station, loadingStationID: env.radioViewModel.loadingStationID,
                         width: width) { play(station) }
    }

    private func play(_ station: RadioStation) {
        Task {
            await env.radioViewModel.play(station: station, using: env.client, player: env.player, toast: toastCenter)
        }
    }
}
