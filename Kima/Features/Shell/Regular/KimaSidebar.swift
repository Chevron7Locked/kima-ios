import SwiftUI

// MARK: - KimaSidebar

/// Left column of the iPad 2-column shell: expanded (236pt, nav rows + playlist stack) or
/// collapsed (68pt icon-only rail);
/// the active row uses a background tint + accent icon/label, since edge stripes wider than a
/// hairline are banned in this design language. The choice persists via `@AppStorage`.
struct KimaSidebar: View {
    @Binding var selection: SidebarItem
    /// The playlist open in the playlists section, marked in the playlist list.
    let openPlaylistId: String?
    let onShowActivity: () -> Void
    let onSelectPlaylist: (String) -> Void

    @Environment(AppEnvironment.self) private var env

    /// Device-local, survives relaunch. No backend.
    @AppStorage("kima.ipadSidebarCollapsed") private var isCollapsed = false

    @State private var playlists: [PlaylistSummary] = []
    @State private var isLoadingPlaylists = false

    static let expandedWidth: CGFloat = 236
    static let collapsedWidth: CGFloat = 68

    private var width: CGFloat { isCollapsed ? Self.collapsedWidth : Self.expandedWidth }
    private var hPad: CGFloat { isCollapsed ? KimaSpacing.sm : KimaSpacing.lg }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, hPad)
                .padding(.top, KimaSpacing.xl)
                .padding(.bottom, KimaSpacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: KimaSpacing.xxl) {
                    navigationIndexSection
                    if !isCollapsed {
                        PlaylistStackSection(
                            playlists: playlists,
                            isLoadingPlaylists: isLoadingPlaylists,
                            openPlaylistId: openPlaylistId,
                            onSelectPlaylist: onSelectPlaylist
                        )
                    }
                }
                .padding(.bottom, KimaSpacing.xl)
            }

            Spacer(minLength: 0)

            footer
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(KimaColor.surface)
        // Bleed the surface into the bottom safe strip so the footer covers content under it.
        .background(KimaColor.surface.ignoresSafeArea(.container, edges: .bottom))
        .overlay(alignment: .trailing) {
            Rectangle().fill(KimaColor.hairline).frame(width: 1)
        }
        .task { await loadPlaylists() }
    }

    // MARK: - Header — mark + wordmark + collapse toggle

    @ViewBuilder
    private var header: some View {
        if isCollapsed {
            VStack(spacing: KimaSpacing.md) {
                KimaMark(living: true).frame(width: 28, height: 28)
                collapseToggle
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: KimaSpacing.sm) {
                KimaMark(living: true).frame(width: 28, height: 28)
                Text("kima")
                    .font(KimaType.wordmark(18))
                    .foregroundStyle(KimaColor.textPrimary)
                    .tracking(1.2)
                Spacer(minLength: 0)
                collapseToggle
            }
        }
    }

    private var collapseToggle: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                isCollapsed.toggle()
            }
        } label: {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(KimaColor.textMuted)
                .frame(width: 30, height: 30)
                .background(KimaColor.surfaceRaised, in: Circle())
                .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "expand sidebar" : "collapse sidebar")
    }

    // MARK: - Navigation Index

    private var navigationIndexSection: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            VStack(spacing: KimaSpacing.xs) {
                ForEach(SidebarItem.indexed) { item in
                    navigationRow(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func navigationRow(_ item: SidebarItem) -> some View {
        let isActive = selection == item
        Button {
            selection = item
        } label: {
            if isCollapsed {
                iconChip(systemName: item.systemImage, isActive: isActive)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            } else {
                HStack(spacing: KimaSpacing.md) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isActive ? KimaColor.brand : KimaColor.textSecondary)
                        .frame(width: 18)

                    Text(item.title.lowercased())
                        .font(KimaType.captionStrong)
                        .tracking(0.1)
                        .foregroundStyle(isActive ? KimaColor.textPrimary : KimaColor.textSecondary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.vertical, KimaSpacing.sm + 2)
                .background(
                    isActive ? KimaColor.brand.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                )
                .padding(.horizontal, KimaSpacing.sm)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// Icon-only chip used by collapsed nav rows and footer buttons — keeps the same
    /// accent-tint active background the expanded rows use.
    private func iconChip(systemName: String, isActive: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isActive ? KimaColor.brand : KimaColor.textSecondary)
            .frame(width: 44, height: 40)
            .background(
                isActive ? KimaColor.brand.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
            )
    }

    // MARK: - Footer — Settings + Activity

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0) {
            KimaHairline()
                .padding(.horizontal, hPad)

            if isCollapsed {
                VStack(spacing: KimaSpacing.sm) {
                    settingsButton
                    activityButton
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, KimaSpacing.md)
            } else {
                // Match the docked player bar's height so the sidebar footer and the bar read as
                // one continuous docked bottom edge — their top hairlines line up across the whole
                // window. Content is vertically centered; the surface bleeds to the screen edge.
                HStack(spacing: KimaSpacing.sm) {
                    settingsButton
                    Spacer(minLength: 0)
                    activityButton
                }
                .padding(.horizontal, KimaSpacing.lg)
                .frame(height: RegularNowPlayingBar.height)
                // Quiet flat docked edge, same solid surface + vibe whisper as the bar, so footer + bar read as one strip.
                .background {
                    ZStack {
                        KimaColor.surfaceRaised
                        LinearGradient(
                            colors: [env.accent.color.opacity(0.10), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        let isActive = selection == .settings
        Button {
            selection = .settings
        } label: {
            if isCollapsed {
                iconChip(systemName: SidebarItem.settings.systemImage, isActive: isActive)
            } else {
                HStack(spacing: KimaSpacing.sm) {
                    Image(systemName: SidebarItem.settings.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                    Text("settings")
                        .font(KimaType.captionStrong)
                        .tracking(0.1)
                }
                .foregroundStyle(isActive ? KimaColor.brand : KimaColor.textSecondary)
                .padding(.horizontal, KimaSpacing.md)
                .padding(.vertical, KimaSpacing.sm)
                .background(
                    isActive ? KimaColor.brand.opacity(0.12) : Color.clear,
                    in: Capsule()
                )
            }
        }
        .buttonStyle(.plain)
        .help(SidebarItem.settings.title)
        .accessibilityLabel(SidebarItem.settings.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    private var activityButton: some View {
        Button(action: onShowActivity) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: env.events.unreadCount > 0 ? "bell.fill" : "bell")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KimaColor.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(KimaColor.surfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))

                if env.events.unreadCount > 0 {
                    KimaCountBadge(count: env.events.unreadCount, dotAbove: 0)
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("activity")
        .accessibilityLabel("activity")
    }

    // MARK: - Data

    private func loadPlaylists() async {
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }
        playlists = (try? await env.client.getPlaylists())?.filter { $0.isHidden != true } ?? []
    }
}
