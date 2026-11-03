import SwiftUI

// MARK: - PlaylistsListView

/// Playlists list screen (port of the web /playlists page): owned + shared playlists in an adaptive
/// cover grid (`LibraryGrid.columns`) with play-from-card, an inline create panel, a hidden-playlists
/// tab and an empty state. Pushed via `LibraryRoute.playlists`. Cards: PlaylistGridCard.swift;
/// mosaic: PlaylistMosaicView.swift.
struct PlaylistsListView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast

    @State private var vm = PlaylistsListViewModel()
    @State private var showingImport = false
    @Binding var path: [LibraryRoute]
    // Keyboard dismissal for the inline create panel (rule: always be able
    // to remove the keyboard).
    @FocusState private var createNameFocused: Bool

    var body: some View {
        ZStack {
            KimaScreenGround()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    headerSection
                    if vm.isLoading && vm.playlists.isEmpty {
                        skeletonGrid
                    } else if let msg = vm.errorMessage, vm.playlists.isEmpty {
                        KimaErrorState(message: msg) { Task { await vm.load(using: env.client) } }
                            .padding(.top, KimaSpacing.xl)
                    } else if vm.displayedPlaylists.isEmpty {
                        emptyState
                            .padding(.horizontal, KimaSpacing.lg)
                            .padding(.top, KimaSpacing.xl)
                    } else {
                        playlistGrid
                    }
                }
            }
            .kimaScrollTopGround()
            .kimaMiniPlayerClearance()
            .scrollBounceBehavior(.basedOnSize)
            .kimaKeyboardSafeCanvas()
        }
        // System back button in a transparent bar, like the other pushed screens.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .task {
            await vm.load(using: env.client)
            #if DEBUG
            // Deep link `-kima-open playlist` (= playlist:first): push the first loaded list. This page is pushed
            // on iPhone (path holds it) and is the playlists section's root on iPad (path empty).
            if DebugDeepLink.requested == "playlist", path.count <= 1, let first = vm.visiblePlaylists.first {
                path.append(.playlistDetail(id: first.id))
            }
            #endif
        }
        .refreshable { await vm.load(using: env.client) }
        .sheet(isPresented: $showingImport) { ImportView().appEnvironment(env, toast) }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Shared editorial masthead — same primitive as Library/Audiobooks/Podcasts,
            // reading whatever's actually on screen (all playlists, or the hidden set).
            KimaScreenHeader(
                title: "playlists",
                statValue: vm.displayedPlaylists.count,
                statLabel: vm.showHiddenTab ? "hidden" : "playlists"
            )

            actionBar
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.bottom, KimaSpacing.sm)

            if vm.isCreating {
                createPanel
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.bottom, KimaSpacing.md)
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: KimaSpacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    vm.isCreating.toggle()
                    if !vm.isCreating { vm.resetCreateState() }
                }
            } label: {
                // The page's primary action: a flat amber pill.
                Label("create", systemImage: "plus")
                    .font(KimaType.captionStrong).tracking(0.1)
                    .foregroundStyle(KimaColor.onBrand)
                    .padding(.horizontal, KimaSpacing.md).padding(.vertical, KimaSpacing.sm)
                    .background(Capsule().fill(KimaColor.brand))
                    .opacity(vm.isCreating ? 0.85 : 1)
                    .kimaHitTarget(growsLayout: false)
            }
            .buttonStyle(.plain)

            Button { showingImport = true } label: {
                Label("import", systemImage: "arrow.down.circle")
                    .font(KimaType.captionStrong).tracking(0.1)
                    .foregroundStyle(KimaColor.textMuted)
                    .playlistsQuietPill()
                    .kimaHitTarget(growsLayout: false)
            }
            .buttonStyle(.plain)

            if !vm.hiddenPlaylists.isEmpty {
                Spacer()
                Button { vm.showHiddenTab.toggle() } label: {
                    Text(vm.showHiddenTab ? "show all" : "hidden (\(vm.hiddenPlaylists.count))")
                        .font(KimaType.meta)
                        .foregroundStyle(vm.showHiddenTab ? KimaColor.textPrimary : KimaColor.textMuted)
                        .playlistsQuietPill()
                        .kimaHitTarget(growsLayout: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Create panel

    private var createPanel: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            HStack(spacing: KimaSpacing.sm) {
                TextField("playlist name…", text: $vm.newPlaylistName)
                    .font(KimaType.body).foregroundStyle(KimaColor.textPrimary)
                    .autocorrectionDisabled()
                    .focused($createNameFocused)
                    .submitLabel(.done)
                    .onSubmit { createNameFocused = false }
                    .padding(.horizontal, KimaSpacing.md).frame(height: 44)
                    .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))
                    .overlay(RoundedRectangle(cornerRadius: KimaRadius.card).strokeBorder(KimaColor.hairline, lineWidth: 1))

                Button { vm.makePublic.toggle() } label: {
                    Text(vm.makePublic ? "public" : "private")
                        .font(KimaType.meta)
                        .foregroundStyle(vm.makePublic ? KimaColor.textPrimary : KimaColor.textMuted)
                        .padding(.horizontal, KimaSpacing.sm).frame(height: 44)
                        .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: KimaRadius.card)
                            .strokeBorder(vm.makePublic ? KimaColor.hairlineStrong : KimaColor.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        if let newId = await vm.submitCreate(using: env.client) {
                            path.append(.playlistDetail(id: newId))
                        }
                    }
                } label: {
                    if vm.isSubmitting {
                        ProgressView().tint(KimaColor.onBrand).frame(width: KimaLayout.minTouchTarget, height: KimaLayout.minTouchTarget)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(KimaColor.onBrand)
                            .frame(width: KimaLayout.minTouchTarget, height: KimaLayout.minTouchTarget)
                    }
                }
                .background(Circle().fill(KimaColor.brand))
                .buttonStyle(.plain)
                .disabled(vm.newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSubmitting)
            }
            if let err = vm.createError {
                Text(err).font(KimaType.meta).foregroundStyle(KimaColor.danger)
            }
        }
    }

    // MARK: - Playlist grid

    private var playlistGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(
                title: vm.showHiddenTab ? "hidden" : "all playlists",
                badge: "\(vm.displayedPlaylists.count)"
            )
            LazyVGrid(columns: LibraryGrid.columns, spacing: KimaSpacing.xl) {
                ForEach(vm.displayedPlaylists) { playlist in
                    PlaylistGridCard(
                        playlist: playlist,
                        isHiddenView: vm.showHiddenTab,
                        onTap: { path.append(.playlistDetail(id: playlist.id)) },
                        onPlay: { Task { await vm.play(playlist: playlist, using: env.client, player: player, toast: toast) } },
                        onToggleHide: { Task { await vm.toggleHide(playlist: playlist, using: env.client, toast: toast) } },
                        isBusy: vm.startingIds.contains(playlist.id)
                    )
                }
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.bottom, KimaSpacing.md)
        }
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: LibraryGrid.columns, spacing: KimaSpacing.xl) {
            ForEach(0..<6, id: \.self) { _ in PlaylistGridCardSkeleton() }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.md)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.lg) {
            if vm.showHiddenTab {
                Text("no hidden playlists")
                    .font(KimaType.meta).foregroundStyle(KimaColor.textMuted).tracking(0.1)
            }
            if !vm.showHiddenTab {
                Button { withAnimation { vm.isCreating = true } } label: {
                    HStack(spacing: KimaSpacing.md) {
                        ZStack {
                            Circle().fill(KimaColor.fillQuiet)
                                .frame(width: 44, height: 44)
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .light)).foregroundStyle(KimaColor.textPrimary)
                        }
                        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                            Text("create your first playlist")
                                .font(KimaType.headline).foregroundStyle(KimaColor.textPrimary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension View {
    /// The bar's quiet outlined pill (import, hidden): surface fill, hairline edge.
    func playlistsQuietPill() -> some View {
        padding(.horizontal, KimaSpacing.md).padding(.vertical, KimaSpacing.sm)
            .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))
            .overlay(RoundedRectangle(cornerRadius: KimaRadius.card).strokeBorder(KimaColor.hairline, lineWidth: 1))
    }
}
