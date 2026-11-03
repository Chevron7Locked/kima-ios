import SwiftUI

// MARK: - PodcastDiscoverySections

/// The lower half of the podcasts page: rows from the categories of the shows you follow ("for you"), Apple's top
/// shows, a few category rows that load as they near the screen, and one "categories" link for the rest.
struct PodcastDiscoverySections: View {
    let vm: PodcastsLibraryViewModel
    let open: (PodcastRoute) -> Void

    var body: some View {
        ForEach(vm.forYou) { row in
            KimaSectionHeader(title: "for you · \(row.category.name.lowercased())",
                              onSeeAll: { open(.chart(categoryId: row.category.id)) })
            if let because = Self.becauseLine(row.because) {
                Text(because)
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .lineLimit(1)
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.bottom, KimaSpacing.sm)
            }
            showRail(row.podcasts)
        }

        if !vm.topShows.isEmpty {
            KimaSectionHeader(title: "top shows", onSeeAll: { open(.chart(categoryId: nil)) })
            showRail(vm.topShows)
        }

        ForEach(vm.rowCategories) { category in
            PodcastCategoryRow(category: category, vm: vm, open: open)
        }

        if !vm.categories.isEmpty {
            Button { open(.categories) } label: {
                HStack {
                    Text("categories")
                        .font(KimaType.section)
                        .foregroundStyle(KimaColor.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(vm.categories.count)")
                        .font(KimaType.caption)
                        .monospacedDigit()
                        .foregroundStyle(KimaColor.textMuted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KimaColor.textMuted)
                }
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.top, KimaSpacing.xl)
                .frame(minHeight: KimaLayout.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("all \(vm.categories.count) categories")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func showRail(_ shows: [DiscoveryPodcast]) -> some View {
        KimaRail(tileWidth: PodcastCardView.cardWidth) { width in
            ForEach(shows) { show in
                PodcastCardView(discovery: show, width: width) { open(.detail(id: show.id)) }
            }
        }
    }

    /// "because you follow a and b" — up to two names, then "and n more". A title's tagline after " | " is dropped.
    static func becauseLine(_ titles: [String]) -> String? {
        let names = titles.map { ($0.components(separatedBy: " | ").first ?? $0).lowercased() }
        switch names.count {
        case 0: return nil
        case 1: return "because you follow \(names[0])"
        case 2: return "because you follow \(names[0]) and \(names[1])"
        default: return "because you follow \(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }
}

// MARK: - PodcastCategoryRow

/// One category's chart as a rail, fetched when the row first nears the screen. While Apple is asked (one chart
/// every few seconds) the rail holds placeholder covers; a failure offers a retry; an empty chart hides the row.
private struct PodcastCategoryRow: View {
    let category: PodcastCategory
    let vm: PodcastsLibraryViewModel
    let open: (PodcastRoute) -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let phase = vm.rowPhases[category.id] ?? .idle
        Group {
            if case .loaded(let ids) = phase, ids.isEmpty {
                EmptyView()
            } else {
                KimaSectionHeader(title: category.name.lowercased(),
                                  onSeeAll: { open(.chart(categoryId: category.id)) })
                switch phase {
                case .failed:
                    Button { load(retry: true) } label: {
                        Text("couldn't reach apple podcasts · try again")
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textSecondary)
                            .frame(minHeight: KimaLayout.minTouchTarget)
                            .padding(.horizontal, KimaSpacing.lg)
                    }
                    .buttonStyle(.plain)
                case .loaded:
                    KimaRail(tileWidth: PodcastCardView.cardWidth) { width in
                        ForEach(vm.shows(inRow: category.id)) { show in
                            PodcastCardView(discovery: show, width: width) { open(.detail(id: show.id)) }
                        }
                    }
                case .idle, .loading:
                    placeholders
                }
            }
        }
        // Keyed on the page's refresh count, so a pull to refresh reloads rows already on screen.
        .task(id: vm.rowGeneration) { await vm.loadRow(category.id, client: env.client) }
    }

    private func load(retry: Bool) { Task { await vm.loadRow(category.id, client: env.client, retry: retry) } }

    private var placeholders: some View {
        KimaRail(tileWidth: PodcastCardView.cardWidth) { width in
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous)
                    .fill(KimaColor.surface)
                    .frame(width: width, height: width)
                    .kimaSkeletonPulse()
            }
        }
        .accessibilityLabel("loading \(category.name.lowercased())")
    }
}

// MARK: - PodcastCategoriesView

/// Every top-level podcast category; a row opens its chart.
struct PodcastCategoriesView: View {
    let categories: [PodcastCategory]
    let open: (PodcastRoute) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                KimaScreenHeader(title: "categories")
                ForEach(categories) { category in
                    Button { open(.chart(categoryId: category.id)) } label: {
                        HStack {
                            Text(category.name.lowercased())
                                .font(KimaType.body)
                                .foregroundStyle(KimaColor.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(KimaColor.textMuted)
                        }
                        .padding(.vertical, KimaSpacing.md)
                        .frame(minHeight: KimaLayout.minTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, KimaSpacing.lg)
                    KimaHairline().padding(.horizontal, KimaSpacing.lg)
                }
            }
        }
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
        .kimaScreenCanvas()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
