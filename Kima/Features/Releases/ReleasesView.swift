import SwiftUI

// MARK: - ReleasesView
//
// Release Radar (Lidarr-backed): stats header, upcoming (soonest first), recent (newest
// first). Empty, error and retry states follow DiscoverView.

struct ReleasesView: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self)    private var toast

    @State private var vm = ReleasesViewModel()

    // MARK: - Body

    var body: some View {
        content
            .task { await env.acquire.refresh(client: env.client) }
    }

    private var content: some View {
        KimaPhaseScreen(phase: vm.phase, retry: { Task { await vm.load(using: env.client) } }) {
            contentFeed
        }
        .task { await vm.load(using: env.client) }
        .refreshable {
            if !(await vm.load(using: env.client)) {
                toast.show("couldn't refresh new releases", style: .error)
            }
        }
    }

    // MARK: - Content feed

    private var contentFeed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KimaScreenHeader(title: "new releases")

                if let radar = vm.radar {
                    statsHeader(radar)
                }

                // §01 — Upcoming releases (soonest first)
                KimaSectionHeader(title: "upcoming")

                if vm.upcoming.isEmpty {
                    emptySectionLabel("no upcoming releases from your artists")
                } else {
                    ForEach(vm.upcoming) { release in
                        releaseRow(release)
                        if release.id != vm.upcoming.last?.id { rowDivider }
                    }
                }

                // §02 — Recent releases (newest first)
                KimaSectionHeader(title: "recent")

                if vm.recent.isEmpty {
                    emptySectionLabel("no recent releases")
                } else {
                    ForEach(vm.recent) { release in
                        releaseRow(release)
                        if release.id != vm.recent.last?.id { rowDivider }
                    }
                }
            }
        }
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
    }

    // MARK: - Stats header

    private func statsHeader(_ radar: ReleasesRadarResponse) -> some View {
        HStack(spacing: KimaSpacing.sm) {
            KimaStatTile(value: "\(radar.monitoredArtistCount)", label: "artists")
            KimaStatTile(value: "\(radar.upcoming.count)",        label: "upcoming")
            KimaStatTile(value: "\(radar.recent.count)",          label: "recent")
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.xl)
        .padding(.bottom, KimaSpacing.sm)
    }

    // MARK: - Row + divider

    private func releaseRow(_ release: ReleaseItem) -> some View {
        ReleaseRowView(
            release: release,
            isDownloading: vm.downloadingMbids.contains(release.albumMbid),
            onDownload: env.acquire.canAcquire ? {
                Task {
                    let result = await vm.download(release: release, using: env.client)
                    toast.show(result.message, style: result.isError ? .error : .success)
                }
            } : nil
        )
    }

    private var rowDivider: some View {
        KimaHairline()
            .padding(.horizontal, KimaSpacing.lg)
    }

    // MARK: - Empty section label

    private func emptySectionLabel(_ message: String) -> some View {
        Text(message)
            .font(KimaType.caption)
            .foregroundStyle(KimaColor.textMuted)
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.vertical, KimaSpacing.xl)
    }
}
