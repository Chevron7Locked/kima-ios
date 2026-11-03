import SwiftUI

// MARK: - Stats: the listener, then the server, one chapter at a time
//
// Chapters are scroll sections with lowercase wording. Amber is only ever data, and music time is an estimate
// that says "about". The admin `system` block is web-only and not modelled here.

struct StatsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm: StatsViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: StatsViewModel(client: env.client))
    }

    private var listening: ListeningStats? { vm.data?.listening }
    private var hasPlays: Bool { (listening?.plays ?? 0) > 0 }

    var body: some View {
        Group {
            if vm.data == nil && !vm.failed {
                KimaLoadingState(onRetry: vm.retry)
                    .frame(maxWidth: .infinity)
            } else if vm.data == nil {
                KimaErrorState(message: "couldn't load stats", onRetry: vm.retry)
            } else {
                content
            }
        }
        .kimaScreenCanvas()
        .navigationTitle("stats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { if vm.data == nil { vm.load() } }
    }

    private var content: some View {
        let period = vm.shownPeriod
        // ScrollViewReader, not .scrollPosition(id:): a nil scrollPosition
        // binding on a LazyVStack makes the page bounce mid-load (run 11 tree:
        // offset -1222 at the first assertion, back to 0 at the screenshot —
        // LazyVStack pruned the header+picker from AX while scrolled).
        return ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: KimaSpacing.xxl) {
                header(period)
                if vm.failed {
                    // A failed period switch keeps the figures already on screen.
                    Text("couldn't load that period · showing \(period.label)")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textSecondary)
                }
                if let l = vm.data?.listening {
                    if hasPlays {
                        StatsOverview(l: l, s: vm.data!.signature, shelf: vm.data!.shelf, period: period)
                        StatsShape(l: l, period: period)
                        StatsTopLists(l: l, period: period)
                        if l.peak != nil {
                            StatsRhythm(l: l, onCell: { dow, hour in
                                // The app root presents the drill (see
                                // NavigationRouter.hourDrill — sheet AX only
                                // publishes from the root).
                                env.router.hourDrill = HourDrill(dow: dow, hour: hour, period: vm.shownPeriod)
                            })
                        }
                        StatsMood(s: vm.data!.signature, analysed: vm.data!.shelf.analysis.done, period: period)
                        StatsEnergy(s: vm.data!.signature)
                    } else {
                        StatsNoPlays(period: period)
                    }
                    StatsUnplayed(shelf: vm.data!.shelf, period: period)
                    StatsAlsoTrue(s: vm.data!.signature, spoken: vm.data!.spoken, l: l, period: period)
                }
                StatsFalseStarts()
                    .id("false-starts")
            }
            .scrollTargetLayout()
            // Pad before the viewport frame: the reverse order puts the padding outside the viewport,
            // so content is 32pt too wide and clips at both edges.
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.bottom, KimaSpacing.lg)
            .kimaViewportWidth()
        }
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
        // The /stats#false-starts target lands at the audit; only that anchor scrolls, otherwise the
        // page starts at the top. Not .scrollPosition(id:): a nil binding on a LazyVStack scrolls to the end.
        .onAppear {
            if env.router.statsScrollToAudit {
                env.router.statsScrollToAudit = false
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo("false-starts", anchor: .top) }
                }
            }
        }
        }
    }

    private func header(_ period: StatsPeriod) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("your listening")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                Spacer()
                if period == .all, hasPlays, let first = listening?.firstPlay {
                    Text("since \(StatsFormat.monthYear(iso: first))")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                }
            }
            StatsPeriodPicker(selection: vm.period, busy: vm.reloading) { vm.period = $0 }
        }
        .padding(.top, KimaSpacing.md)
    }
}

// MARK: - Overview

private struct StatsOverview: View {
    let l: ListeningStats
    let s: Signature
    let shelf: ShelfStats
    let period: StatsPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xl) {
            // The hours are an estimate and say so; these four counts are exact.
            Text("about \(StatsFormat.hours(l.estimatedSeconds)) hours of music\(period.sentence.isEmpty ? "" : " · \(period.sentence)")")
                .font(KimaType.statement)
                .foregroundStyle(KimaColor.textPrimary)
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)

            // Phone-width layout: 2×2, not one cramped 4-across row —
            // the reference keeps figures in a column/pair rhythm, never a single bunched line.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: KimaSpacing.lg) {
                StatsReading(value: l.plays.formatted(.number), label: "plays")
                StatsReading(value: l.distinctArtists.formatted(.number), label: "artists")
                StatsReading(value: l.distinctAlbums.formatted(.number), label: "albums")
                StatsReading(value: "\(StatsFormat.percent(part: shelf.tracks.heard, whole: shelf.tracks.total))%", label: "of library played",
                             scope: period == .all ? nil : "all time")
            }

            VStack(alignment: .leading, spacing: 0) {
                if let peak = l.peak {
                    StatsFact(value: StatsFormat.whenLabel(weekday: peak.weekday, hour: peak.hour),
                              note: "busiest hour of the week")
                }
                if let c = s.concentration {
                    StatsFact(value: "\(c.forHalf) track\(c.forHalf == 1 ? "" : "s")",
                              note: c.forHalf == 1 ? "makes up half your plays" : "make up half your plays")
                }
                if let k = s.key {
                    StatsFact(value: "\(Int(k.minorPct.rounded()))% minor key",
                              note: k.top.first.map { "top key: \($0.key.lowercased())" })
                }
                if let h = s.albumHabit {
                    StatsFact(value: "\(Int(h.inOrderPct.rounded()))%", note: "played in album order")
                }
                if let e = s.era {
                    StatsFact(value: String(e.medianYear), note: "median release year")
                }
            }
            if let c = s.concentration {
                StatsPlayCore(count: c.forHalf, period: period)
            }
        }
    }
}

private struct StatsReading: View {
    let value: String
    let label: String
    var scope: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            Text(value)
                .font(KimaType.figure)
                .foregroundStyle(KimaColor.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
            if let scope {
                Text(scope)
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textFaint)
            }
        }
    }
}

private struct StatsFact: View {
    let value: String
    let note: String?
    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.sm) {
                Text(value)
                    .font(KimaType.figure)
                    .foregroundStyle(KimaColor.textPrimary)
                    .monospacedDigit()
                if let note {
                    Text(note)
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textSecondary)
                }
            }
            .padding(.vertical, KimaSpacing.md)
            KimaHairline()
        }
    }
}

private struct StatsNoPlays: View {
    let period: StatsPeriod
    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.lg) {
            Text(period == .all ? "no plays yet" : "no plays in this period")
                .font(KimaType.statement)
                .foregroundStyle(KimaColor.textPrimary)
            Text(period == .all
                 ? "a play counts after half the track"
                 : "try a longer period")
                .font(KimaType.body)
                .foregroundStyle(KimaColor.textSecondary)
        }
    }
}

// MARK: - Period control (web PeriodPicker: active option underlined in brand)

struct StatsPeriodPicker: View {
    let selection: StatsPeriod
    let busy: Bool
    let onChange: (StatsPeriod) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.lg) {
            ForEach(StatsPeriod.allCases) { p in
                Button { onChange(p) } label: {
                    Text(p.label)
                        .font(KimaType.headline)
                        .foregroundStyle(p == selection ? KimaColor.textPrimary : KimaColor.textMuted)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(p == selection ? KimaColor.brand : .clear)
                                .frame(height: 1.5)
                        }
                        .padding(.bottom, KimaSpacing.xs)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(busy ? 0.5 : 1)
        .animation(.default, value: busy)
        // No container accessibilityLabel — it propagates to the buttons and
        // shadows their option text from XCUITest (the moodmix lesson).
    }
}
