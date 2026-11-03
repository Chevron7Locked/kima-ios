import SwiftUI

// MARK: - PodcastChartView

/// One category's Apple chart (nil = the overall "top shows" chart): a grid in chart order, 48 at a time, the next page
/// loading as the end scrolls into view. A category with sub-categories (or one of them) shows its family as a row
/// of chips that switch the chart in place. `onPodcastTap` opens the show.
struct PodcastChartView: View {
    let onPodcastTap: (DiscoveryPodcast) -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var vm: PodcastChartViewModel

    init(categoryId: Int?, onPodcastTap: @escaping (DiscoveryPodcast) -> Void) {
        self.onPodcastTap = onPodcastTap
        _vm = State(initialValue: PodcastChartViewModel(categoryId: categoryId))
    }

    var body: some View {
        Group {
            switch vm.phase {
            case .loading:
                KimaLoadingState(onRetry: reload)
            case .noSuchCategory:
                KimaErrorState(message: "no such category", onRetry: reload)
            case .unreachable:
                KimaErrorState(message: "couldn't reach apple podcasts", onRetry: reload)
            case .loaded:
                content
            }
        }
        .kimaScreenCanvas()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(client: env.client) }
    }

    private func reload() { Task { await vm.load(client: env.client) } }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                KimaScreenHeader(title: vm.title)

                if !vm.family.isEmpty {
                    chips
                        .padding(.bottom, KimaSpacing.lg)
                }

                if vm.shows.isEmpty && !vm.isLoadingMore && !vm.loadMoreFailed {
                    Text("apple has no chart for this category right now")
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, KimaSpacing.huge)
                } else {
                    grid
                }

                if vm.isLoadingMore {
                    ProgressView()
                        .tint(KimaColor.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, KimaSpacing.xl)
                } else if vm.loadMoreFailed {
                    Button { Task { await vm.loadMore(client: env.client) } } label: {
                        Text("couldn't reach apple podcasts · try again")
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: KimaLayout.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, KimaSpacing.md)
                }
            }
        }
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
    }

    private var grid: some View {
        KimaCardGrid(count: vm.shows.count, minimum: 140, maximum: 180) {
            ForEach(Array(vm.shows.enumerated()), id: \.element.id) { index, show in
                PodcastCardView(discovery: show, width: nil) { onPodcastTap(show) }
                    // On scrolling into view, not on appearing: a short grid builds every card when it opens.
                    .onScrollVisibilityChange { visible in
                        guard visible, index >= vm.shows.count - 6 else { return }
                        Task { await vm.loadMore(client: env.client) }
                    }
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
    }

    /// The category's family as plain text pills; the shown one is the amber "on" ring.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KimaSpacing.sm) {
                ForEach(vm.family) { chip in
                    let isOn = chip.id == vm.categoryId
                    Button { switchTo(chip.id) } label: {
                        Text(chip.name.lowercased())
                            .font(KimaType.caption)
                            .foregroundStyle(isOn ? KimaColor.textPrimary : KimaColor.textSecondary)
                            .padding(.horizontal, KimaSpacing.md)
                            .frame(minHeight: 32)
                            .overlay(Capsule().strokeBorder(isOn ? KimaColor.brand.opacity(0.6) : KimaColor.hairlineStrong,
                                                            lineWidth: 1))
                            .kimaHitTarget(growsLayout: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, KimaSpacing.lg)
        }
    }

    private func switchTo(_ id: Int) {
        Task { await vm.select(id, client: env.client) }
    }
}
