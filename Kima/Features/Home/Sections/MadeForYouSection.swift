import SwiftUI

// MARK: - MixCard

/// Card for a programmatic mix from GET /mixes: a 2×2 mosaic of the first four `coverUrls`
/// with empty cells when there are fewer (web MixesGrid → MediaCard), the mix name, and its track count.
private struct MixCard: View {
    let mix: HomeMix
    let onTap: () -> Void
    /// The play badge's action. Tapping the card plays the mix (see the note above), and the
    /// badge makes that visible and spin while the mix's tracks are being fetched.
    let onPlay: () -> Void
    /// The mix whose track list is being fetched: the badge spins and ignores repeat taps.
    var isBusy: Bool = false
    var width: CGFloat = 148

    var body: some View {
        // openID (not `.accessibilityIdentifier` on the whole card): the identifier names the
        // card's OPEN targets for UI tests, and on the container it would override the play
        // badge's own "play-badge" — the badge is what the play-feedback suites watch spin.
        KimaCoverCard(title: mix.name,
                      subtitle: mix.trackCount == 1 ? "1 track" : "\(mix.trackCount) tracks",
                      isBusy: isBusy,
                      onPlay: onPlay,
                      onTap: onTap,
                      openID: "mix-card") {
            PlaylistMosaicView(coverIds: mix.coverUrls, cellSize: 150, fitsCovers: true)
        }
        .frame(width: width)
    }
}

// MARK: - MadeForYouSection

/// Home section for programmatic mixes ("made for you"), backed by GET /mixes. The header has a mood mixer and a
/// refresh button; the refresh spinner reads `vm.isRefreshingMixes` here so only this section re-renders.
struct MadeForYouSection: View {
    let mixes: [HomeMix]
    /// The parent HomeViewModel — read directly for `isRefreshingMixes` (see above).
    let vm: HomeViewModel
    /// POST /mixes/refresh, then swap the rail.
    let onRefresh: () async -> Void
    /// Silent GET /mixes after the mood mixer saves a mix.
    let onMixesReload: () async -> Void
    /// GET /mixes/:id for the tracks, then play from the top.
    let onPlayMix: (HomeMix) async -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast
    @State private var showMoodMixer = false
    @State private var confirmingRefresh = false

    var body: some View {
        VStack(spacing: 0) {
            KimaSectionHeader(title: "made for you") {
                headerTrailing
            }
            KimaRail(tileWidth: 148) { width in
                ForEach(mixes) { mix in
                    MixCard(mix: mix,
                            onTap: { Task { await onPlayMix(mix) } },
                            onPlay: { Task { await onPlayMix(mix) } },
                            isBusy: vm.startingIds.contains(mix.id),
                            width: width)
                }
            }
        }
        .sheet(isPresented: $showMoodMixer) {
            MoodMixerView(onMixesReload: onMixesReload)
                .appEnvironment(env, toast)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(
                    LinearGradient(
                        colors: [KimaColor.surface, KimaColor.base],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    // MARK: - Header trailing — mood + refresh side by side

    private var headerTrailing: some View {
        HStack(spacing: KimaSpacing.sm) {
            moodMixerButton
            refreshButton
        }
        // Keep intrinsic size — never let the header row compress these into wrapped text.
        // The title yields via minimumScaleFactor instead.
        .fixedSize()
    }

    private var moodMixerButton: some View {
        Button { showMoodMixer = true } label: {
            HStack(spacing: KimaSpacing.xs) {
                Text("mood")
                    .font(KimaType.meta)
                    .tracking(0.1)
            }
            .foregroundStyle(KimaColor.textPrimary)
            .padding(.horizontal, KimaSpacing.sm)
            .padding(.vertical, KimaSpacing.xs)
            .background(KimaColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(KimaColor.hairlineStrong, lineWidth: 1))
            // 44pt-tall hit area around the small pill without growing the header row.
            .padding(.vertical, KimaSpacing.md)
            .contentShape(Rectangle())
            .padding(.vertical, -KimaSpacing.md)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mood-mixer-open")
    }

    // Icon-only: the spinner is the "refreshing" state; the arrow reads as refresh.
    private var refreshButton: some View {
        Button {
            confirmingRefresh = true
        } label: {
            Group {
                if vm.isRefreshingMixes {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                        .tint(KimaColor.textMuted)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KimaColor.textMuted)
                }
            }
            .frame(width: 30, height: 26)
            .background(KimaColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
            // 44pt hit area around the small capsule without growing the header row.
            .padding(.horizontal, KimaSpacing.sm)
            .padding(.vertical, KimaSpacing.md)
            .contentShape(Rectangle())
            .padding(.horizontal, -KimaSpacing.sm)
            .padding(.vertical, -KimaSpacing.md)
        }
        .buttonStyle(.plain)
        .disabled(vm.isRefreshingMixes)
        .accessibilityLabel(vm.isRefreshingMixes ? "refreshing mixes" : "refresh mixes")
        .accessibilityIdentifier("mixes-refresh")
        .confirmationDialog("make new mixes?", isPresented: $confirmingRefresh, titleVisibility: .visible) {
            Button("make new mixes") { Task { await onRefresh() } }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("picks new songs for all \(mixes.count) mixes. the songs in them now go away.")
        }
    }
}
