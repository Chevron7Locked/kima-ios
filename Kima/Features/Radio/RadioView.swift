import SwiftUI

// MARK: - RadioView

/// Full Library Radio screen (the /radio destination):
/// hero, Quick Start, By Mood, By Genre, By Decade, How It Works. Uses the shared `env.radioViewModel`
/// (no duplicate fetch from Home) with the full uncapped genre/decade lists; the home rail
/// applies its own caps. Section headers use KimaSectionHeader; subviews are in RadioViewComponents.swift.
struct RadioView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self)    private var toastCenter
    @Environment(PlaybackController.self) private var player

    /// The server has sound analysis (workout and mood stations); unknown counts as yes until it answers.
    private var moodsAvailable: Bool { player.vibeEmbeddingsAvailable != false }

    /// Station chips sit a small step apart both ways, so a grid of them reads as one group.
    private let chipColumns = [GridItem(.adaptive(minimum: 155), spacing: KimaSpacing.sm)]

    // MARK: - Derived values

    private var totalStationCount: Int {
        let vm = env.radioViewModel
        var n = vm.quickStations(moodsAvailable: moodsAvailable).count
        if moodsAvailable, case .loaded(let m) = vm.moodsPhase { n += m.count }
        if case .loaded(let g) = vm.genresPhase  { n += g.count }
        if case .loaded(let d) = vm.decadesPhase { n += d.count }
        return n
    }

    private var isLoading: Bool {
        let vm = env.radioViewModel
        if case .loading = vm.moodsPhase   { return true }
        if case .loading = vm.genresPhase  { return true }
        if case .loading = vm.decadesPhase { return true }
        return false
    }

    private var moodsEmpty: Bool {
        if case .loaded(let m) = env.radioViewModel.moodsPhase { return m.isEmpty }
        return false
    }

    private var moodCountLabel: String? {
        if case .loaded(let m) = env.radioViewModel.moodsPhase { return "\(m.count) \(m.count == 1 ? "mood" : "moods")" }
        return nil
    }

    private var genreCountLabel: String? {
        if case .loaded(let g) = env.radioViewModel.genresPhase { return "\(g.count) \(g.count == 1 ? "genre" : "genres")" }
        return nil
    }

    private var decadeCountLabel: String? {
        if case .loaded(let d) = env.radioViewModel.decadesPhase { return "\(d.count) \(d.count == 1 ? "decade" : "decades")" }
        return nil
    }

    // MARK: - Body

    var body: some View {
        let vm = env.radioViewModel
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    RadioHeroView(stationCount: totalStationCount, isLoading: isLoading)

                    // Quick Start — 4 static stations, always available
                    sectionBlock(
                        title: "quick start"
                    ) {
                        KimaAdaptiveGrid(spacing: KimaSpacing.sm, rowSpacing: KimaSpacing.sm) {
                            ForEach(vm.quickStations(moodsAvailable: moodsAvailable)) { station in
                                RadioStationTile(station: station, loadingStationID: vm.loadingStationID) { play(station) }
                            }
                        }
                    }

                    // By Mood — the server's mood stations as stacks of their first albums; only where the sound analysis runs.
                    if moodsAvailable && (!moodsEmpty || vm.moodAnalysisPercent != nil) {
                        sectionBlock(title: "by mood", countLabel: moodsEmpty ? nil : moodCountLabel) {
                            if let percent = vm.moodAnalysisPercent {
                                Text("mood stations fill in as songs are analysed · \(percent)%")
                                    .font(KimaType.meta.monospacedDigit())
                                    .foregroundStyle(KimaColor.textMuted)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, KimaSpacing.md)
                            }
                            // Rows sit further apart than covers sit from their label, so each label stays with its covers.
                            KimaAdaptiveGrid(spacing: KimaSpacing.md, rowSpacing: KimaSpacing.xl) {
                                switch vm.moodsPhase {
                                case .loading:
                                    MoodStationPlaceholders(failed: false) {}
                                case .failed:
                                    MoodStationPlaceholders(failed: true) {
                                        Task { await vm.retryMoods(using: env.client) }
                                    }
                                case .loaded(let stations):
                                    ForEach(stations) { station in
                                        MoodStationTile(station: station) { play(station) }
                                    }
                                }
                            }
                        }
                        .id("kimaRadioMoods")
                    }

                    // By Genre — dynamic; count ≥ 15 filter applied in RadioViewModel
                    sectionBlock(
                        title: "by genre",
                        countLabel: genreCountLabel,
                        countColor: KimaColor.textMuted
                    ) {
                        phaseContent(
                            phase: vm.genresPhase,
                            errorMessage: "couldn't load genre stations.",
                            onRetry: { Task { await vm.retryGenres(using: env.client) } }
                        )
                    }

                    // By Decade — dynamic; no cap on the Radio page
                    sectionBlock(
                        title: "by decade",
                        countLabel: decadeCountLabel,
                        countColor: KimaColor.textMuted
                    ) {
                        phaseContent(
                            phase: vm.decadesPhase,
                            errorMessage: "couldn't load decade stations.",
                            onRetry: { Task { await vm.retryDecades(using: env.client) } }
                        )
                    }

                    // How It Works — static info panel
                    HowItWorksPanel()
                        .padding(.horizontal, KimaSpacing.lg)
                        .padding(.top, KimaSpacing.xxl)
                }
            }
            .kimaScrollTopGround()
            #if DEBUG
            // Screenshot hook: `-kima-scroll-moods` scrolls to the mood stations.
            .task {
                guard CommandLine.arguments.contains("-kima-scroll-moods") else { return }
                try? await Task.sleep(for: .seconds(2))
                proxy.scrollTo("kimaRadioMoods", anchor: .top)
            }
            #endif
        }
        .kimaMiniPlayerClearance()
        // New genres and decades from an import show up without relaunching the app.
        .refreshable {
            if await !env.radioViewModel.refresh(using: env.client) {
                toastCenter.show("couldn't refresh radio stations", style: .error)
            }
        }
        .background(KimaScreenGround())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // loadIfNeeded is a no-op if LibraryRadioSection already started the fetch on Home.
            await env.radioViewModel.loadIfNeeded(using: env.client)
            // The analysis moves on while the app runs, so its progress is asked again each time the page opens.
            await env.radioViewModel.refreshMoodProgress(using: env.client)
        }
        .task { await player.checkVibeAvailability(client: env.client) }
    }

    // MARK: - Play

    private func play(_ station: RadioStation) {
        Task {
            await env.radioViewModel.play(
                station: station,
                using: env.client,
                player: env.player,
                toast: toastCenter
            )
        }
    }

    // MARK: - Section block

    @ViewBuilder
    private func sectionBlock<Content: View>(
        title: String,
        countLabel: String? = nil,
        countColor: Color = KimaColor.textMuted,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: title) {
                if let countLabel {
                    Text(countLabel)
                        .font(KimaType.meta.monospacedDigit())
                        .foregroundStyle(countColor)
                        .lineLimit(1)
                }
            }
            content()
                .padding(.horizontal, KimaSpacing.lg)
        }
    }

    // MARK: - Phase content

    @ViewBuilder
    private func phaseContent(
        phase: LoadPhase<[RadioStation]>,
        errorMessage: String,
        onRetry: @escaping () -> Void
    ) -> some View {
        switch phase {
        case .loading:
            SkeletonGrid(columns: chipColumns)
        case .failed:
            KimaErrorState(message: errorMessage, onRetry: onRetry)
        case .loaded(let stations):
            KimaAdaptiveGrid(spacing: KimaSpacing.sm, rowSpacing: KimaSpacing.sm) {
                ForEach(stations) { station in
                    RadioStationTile(station: station, loadingStationID: env.radioViewModel.loadingStationID) { play(station) }
                }
            }
        }
    }
}
