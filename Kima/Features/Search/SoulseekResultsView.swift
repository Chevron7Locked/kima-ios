import SwiftUI

// MARK: - Client-side format filter / sort
//
// The server returns everything it has accumulated for the search session; narrowing and
// ordering happen entirely on-device against `vm.soulseekResults`.

private enum SoulseekFormatFilter: String, CaseIterable, Identifiable {
    case all, flac, kbps320, kbps256

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:     "all"
        case .flac:    "FLAC"
        case .kbps320: "320+"
        case .kbps256: "256+"
        }
    }

    /// Lossless (FLAC) always passes a bitrate floor — bitrate doesn't apply to it.
    func matches(_ result: SoulseekResult) -> Bool {
        switch self {
        case .all:     return true
        case .flac:    return result.format.lowercased() == "flac"
        case .kbps320: return result.format.lowercased() == "flac" || result.bitrate >= 320
        case .kbps256: return result.format.lowercased() == "flac" || result.bitrate >= 256
        }
    }
}

private enum SoulseekSort: String, CaseIterable, Identifiable {
    case quality, bitrate, size

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quality: "quality"
        case .bitrate: "bitrate"
        case .size:    "size"
        }
    }
}

// MARK: - SoulseekResultsView
// Rendered by `SearchView.contentArea` when `vm.activeFilter == .soulseek`. Soulseek hits are a flat P2P listing,
// each tied to a peer and file with no artist/album sectioning, so this view has its own client-side
// format filter and sort instead of reusing `SearchResultSections`.

struct SoulseekResultsView: View {
    let vm: SearchViewModel

    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    @State private var formatFilter: SoulseekFormatFilter = .all
    @State private var sort: SoulseekSort = .quality

    // MARK: - Body

    var body: some View {
        results
            .task { await env.acquire.refresh(client: env.client) }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if env.acquire.isLocked {
                    Text(AcquirePermission.lockedLabel)
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                        .padding(.horizontal, KimaSpacing.lg)
                        .padding(.top, KimaSpacing.sm)
                }
                statusLine
                if !vm.soulseekResults.isEmpty {
                    controls
                }
                resultsList
                Color.clear.frame(height: KimaSpacing.lg)
            }
        }
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
    }

    // MARK: - Status line

    private var statusLine: some View {
        HStack(spacing: KimaSpacing.sm) {
            Text(statusText)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)

            if vm.isSoulseekSearching {
                ProgressView()
                    .controlSize(.mini)
                    .tint(KimaColor.textMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.lg)
        .padding(.bottom, KimaSpacing.sm)
    }

    private var statusText: String {
        if vm.soulseekResults.isEmpty && vm.isSoulseekSearching {
            return "searching Soulseek…"
        }
        let userCount   = Set(vm.soulseekResults.map(\.username)).count
        let resultWord  = vm.soulseekResults.count == 1 ? "result" : "results"
        let userWord    = userCount == 1 ? "user" : "users"
        return "\(vm.soulseekResults.count) \(resultWord) · \(userCount) \(userWord)"
    }

    // MARK: - Controls (format filter + sort)

    private var controls: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            KimaSegmented(
                options: SoulseekFormatFilter.allCases.map { ($0, $0.label) },
                selection: $formatFilter
            )
            sortRow
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.bottom, KimaSpacing.md)
    }

    private var sortRow: some View {
        HStack(spacing: KimaSpacing.sm) {
            Text("sort")
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
                .tracking(0.1)

            ForEach(SoulseekSort.allCases) { option in
                let selected = sort == option
                Button {
                    sort = option
                } label: {
                    Text(option.label)
                        .font(KimaType.meta)
                        .foregroundStyle(selected ? KimaColor.textPrimary : KimaColor.textMuted)
                        .tracking(0.1)
                        .padding(.horizontal, KimaSpacing.sm)
                        .padding(.vertical, KimaSpacing.xs)
                        .background(selected ? KimaColor.surface : .clear, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(selected ? KimaColor.hairline : .clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Results list

    @ViewBuilder
    private var resultsList: some View {
        let filtered = filteredSortedResults
        if filtered.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ForEach(filtered) { result in
                    SoulseekResultRow(
                        result: result,
                        isDownloading: vm.downloadingKeys.contains(result.id),
                        onDownload: env.acquire.canAcquire
                            ? { vm.downloadSoulseek(result, client: env.client, toast: toast) } : nil
                    )
                    if result.id != filtered.last?.id {
                        KimaHairline()
                            .padding(.leading, KimaSpacing.lg + 44 + KimaSpacing.md)
                    }
                }
            }
        }
    }

    private var filteredSortedResults: [SoulseekResult] {
        let filtered = vm.soulseekResults.filter { formatFilter.matches($0) }
        switch sort {
        case .quality:
            // Lossless first (irrespective of its usually-absent bitrate tag), then by bitrate.
            return filtered.sorted { lhs, rhs in
                let lLossless = lhs.format.lowercased() == "flac"
                let rLossless = rhs.format.lowercased() == "flac"
                if lLossless != rLossless { return lLossless }
                return lhs.bitrate > rhs.bitrate
            }
        case .bitrate:
            return filtered.sorted { $0.bitrate > $1.bitrate }
        case .size:
            return filtered.sorted { $0.size > $1.size }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: KimaSpacing.lg) {
            ZStack {
                Circle()
                    .fill(KimaColor.surface)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(KimaColor.textMuted)
            }

            VStack(spacing: KimaSpacing.sm) {
                Text(vm.isSoulseekSearching ? "searching…" : "no results. try a shorter search.")
                    .font(KimaType.headline)
                    .foregroundStyle(KimaColor.textPrimary)
                    .multilineTextAlignment(.center)
                if !vm.isSoulseekSearching {
                    Text("Soulseek results can take a few seconds.")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, KimaSpacing.xl)
        .padding(.top, KimaSpacing.huge)
        .frame(maxWidth: .infinity)
    }
}
