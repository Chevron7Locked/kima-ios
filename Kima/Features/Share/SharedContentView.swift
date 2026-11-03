import SwiftUI

// MARK: - SharedContentView

/// Public share viewer for kima://share/<token> links and in-app share sheets. Self-contained:
/// unauthenticated /api/share/:token calls and its own AVPlayer for previews. Entity bodies
/// live in adjacent files.
struct SharedContentView: View {
    let shareToken: String
    let serverBaseURL: URL

    @State private var vm: SharedContentViewModel
    @Environment(\.dismiss) private var dismiss

    init(shareToken: String, serverBaseURL: URL) {
        self.shareToken    = shareToken
        self.serverBaseURL = serverBaseURL
        _vm = State(wrappedValue: SharedContentViewModel(token: shareToken, baseURL: serverBaseURL))
    }

    var body: some View {
        ZStack {
            AmbientFieldBackdrop(palette: nil).ignoresSafeArea()
            switch vm.loadState {
            case .loading:
                loadingView
            case .loaded(let content):
                loadedView(content)
            case .notFound:
                emptyState(
                    icon: "link.badge.exclamationmark",
                    title: "link unavailable",
                    subtitle: "this link has expired, been revoked, or doesn't exist."
                )
            case .error(let msg):
                VStack(spacing: 0) {
                    closeButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding([.top, .trailing], KimaSpacing.lg)
                    KimaErrorState(message: msg) { Task { await vm.load() } }
                }
            }
        }
        .task { await vm.load() }
        .onDisappear { vm.stopPlayback() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 0) {
            closeButton
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding([.top, .trailing], KimaSpacing.lg)
            KimaLoadingState { Task { await vm.load() } }
        }
    }

    // MARK: - Empty / error states

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 0) {
            closeButton
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding([.top, .trailing], KimaSpacing.lg)
            Spacer()
            VStack(spacing: KimaSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(KimaColor.textMuted)
                Text(title)
                    .font(KimaType.meta)
                    .foregroundStyle(KimaColor.textMuted)
                    .tracking(0.1)
                Text(subtitle)
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, KimaSpacing.xxl)
            }
            Spacer()
        }
    }

    // MARK: - Entity dispatch

    @ViewBuilder
    private func loadedView(_ content: SharedContent) -> some View {
        // Cap to 720 on wide screens (iPad); no-op on iPhone (width always < 720).
        switch content.entity {
        case .playlist(let playlist):
            SharedPlaylistBody(playlist: playlist, vm: vm, dismiss: dismiss)
                .kimaReadableWidth()
                .frame(maxWidth: .infinity)
        case .track(let track):
            SharedTrackBody(track: track, vm: vm, dismiss: dismiss)
                .kimaReadableWidth()
                .frame(maxWidth: .infinity)
        case .album(let album):
            SharedAlbumBody(album: album, vm: vm, dismiss: dismiss)
                .kimaReadableWidth()
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Close button

    /// Close for the loading and error states; the entity bodies place their own.
    private var closeButton: some View {
        KimaCloseButton(label: "close", id: "share-close", kind: .screen) { dismiss() }
    }
}
