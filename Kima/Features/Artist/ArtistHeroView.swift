import SwiftUI

/// Artist hero: rounded photo, metadata and action bar; the page pins `ArtistHeroBackdrop` behind it.
/// The backdrop's gradient stops: vibrant 0.30/0.40,
/// darkVibrant 0.60, darkMuted 0.90, then `KimaColor.base`).
struct ArtistHeroView: View {
    let artist: Artist
    let source: ArtistSource
    let albums: [Album]
    let isLoadingAction: Bool
    let onPlayAll: () -> Void
    let onShuffle: () -> Void
    let onRadio: (() -> Void)?       // nil → button hidden (discovery artists)
    let onDownloadAll: () -> Void
    /// Opens the metadata editor from the action row's menu; nil for artists not in the library.
    var onEdit: (() -> Void)? = nil
    /// Top safe-area inset — pads the hero CONTENT below the notch/nav bar while the detail
    /// ScrollView bleeds the backdrop under the status bar (the backdrop fills behind this pad).
    var topSafeInset: CGFloat = 0

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showCoverViewer = false
    @State private var confirmingDownload = false

    private var coverId: String? { Self.coverId(for: artist) }

    /// The artist's own photo if it has one, else the library's.
    static func coverId(for artist: Artist) -> String? { artist.userHeroUrl ?? artist.coverArt ?? artist.image }
    private var ownedAlbums: [Album] { albums.filter { $0.owned == true } }

    var body: some View {
        hero
            .task { await env.acquire.refresh(client: env.client) }
    }

    private var hero: some View {
        // The page draws the cover-colour backdrop (ArtistHeroBackdrop) behind the hero at its height.
        VStack(alignment: .leading, spacing: 0) {
            heroContent
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.top, KimaSpacing.xl + topSafeInset)
                .padding(.bottom, KimaSpacing.lg)

            actionBar
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.bottom, KimaSpacing.xl)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Tap the photo → open it full-screen (owned bool; presenter dismisses via onClose).
        .fullScreenCover(isPresented: $showCoverViewer) {
            CoverImageViewer(
                coverId: coverId,
                size: 1024,
                title: artist.effectiveName,
                subtitle: "artist",
                onClose: { showCoverViewer = false }
            )
            .appEnvironment(env, toast)
        }
    }

    // MARK: - Hero content

    /// Side of the artist photo: bigger on regular width.
    private var photoSide: CGFloat { sizeClass == .regular ? KimaLayout.heroCoverRegular : 120 }

    private var heroContent: some View {
        HStack(alignment: .bottom, spacing: KimaSpacing.xl) {
            // Artist photo
            CoverArtImage(
                coverId: coverId,
                size: 512,
                cornerRadius: KimaRadius.hero
            )
            .frame(width: photoSide, height: photoSide)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 8)
            .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { showCoverViewer = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("opens the photo full screen")

              // Name + metadata column
              VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                  KimaKicker(title: "artist")

                // Name + Edited badge. The name is the screen's one hero name: two lines at most, shrinking to fit.
                HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.sm) {
                    Text(artist.effectiveName.lowercased())
                        .font(KimaType.pageTitle)
                        .foregroundStyle(KimaColor.textPrimary)
                        .tracking(-0.4)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)

                    if artist.hasUserOverrides == true {
                        KimaTag(text: "edited", tone: .strong).padding(.top, KimaSpacing.xs)
                    }
                }

                // Listeners · album count · owned count — quiet mono meta line, NOT a
                // boxed stat card. "Owned" reads in the adaptive accent as the one
                // meaningful highlight.
                metadataLine
            }
        }
    }

    private var metadataLine: some View {
        let parts = metadataParts
        return Group {
            if !parts.isEmpty {
                HStack(spacing: KimaSpacing.xs) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { idx, part in
                        if idx > 0 {
                            Text("•")
                                .font(KimaType.meta)
                                .foregroundStyle(KimaColor.textMuted)
                        }
                        Text(part.value)
                            .font(KimaType.meta)
                            .foregroundStyle(part.accent ? KimaColor.textPrimary : KimaColor.textSecondary)
                    }
                }
            }
        }
    }

    private struct MetaPart { let value: String; let accent: Bool }

    private var metadataParts: [MetaPart] {
        var parts: [MetaPart] = []
        if let listeners = artist.listeners, listeners > 0 {
            parts.append(MetaPart(value: listeners.abbreviatedCount + " listeners", accent: false))
        }
        if !albums.isEmpty {
            parts.append(MetaPart(value: "\(albums.count) album\(albums.count == 1 ? "" : "s")", accent: false))
            if !ownedAlbums.isEmpty {
                parts.append(MetaPart(value: "\(ownedAlbums.count) owned", accent: true))
            }
        }
        return parts
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: KimaSpacing.md) {
            let hasOwned = !ownedAlbums.isEmpty

            // Play / Pause — the view's one amber control, a flat disc.
            KimaHeroPlayButton(isPlaying: player.isPlaying && isPlayingThisArtist, label: "play all") {
                if player.isPlaying && isPlayingThisArtist { player.pause() }
                else { onPlayAll() }
            }
            .disabled(!hasOwned && source == .library)
            .opacity((!hasOwned && source == .library) ? 0.4 : 1)

            // Shuffle and radio: quiet labeled pills, so the amber play stays the one loud control.
            if hasOwned {
                KimaActionPill(title: "shuffle", systemImage: "shuffle", action: onShuffle)
            }

            // Radio — library artists only
            if let onRadio {
                KimaActionPill(title: "radio", systemImage: "dot.radiowaves.left.and.right", action: onRadio)
            }

            // Play all / shuffle / radio fetch the artist's tracks first.
            if isLoadingAction {
                ProgressView().tint(KimaColor.brand)
            }

            Spacer(minLength: 0)

            moreMenu
        }
        // On the whole row rather than the menu, so the iPad popover has a stable anchor.
        .confirmationDialog(downloadTitle(count: availableCount), isPresented: $confirmingDownload,
                            titleVisibility: .visible) {
            Button(availableCount > 0 ? "download \(albumCount(availableCount))" : "download all",
                   action: onDownloadAll)
            Button("cancel", role: .cancel) {}
        } message: {
            Text("your server downloads every album by \(artist.effectiveName.lowercased()) you don't have yet.")
        }
    }

    /// Albums by this artist not in the library yet.
    private var availableCount: Int { albums.filter { $0.owned != true }.count }

    /// Download all and edit: rare actions, one tap away. Download all asks first.
    @ViewBuilder
    private var moreMenu: some View {
        // Download All — discovery artists or when there are available albums
        let showDownload = env.acquire.canAcquire && (source == .discovery || availableCount > 0)
        if showDownload || onEdit != nil {
            KimaMoreMenu(label: "artist actions") {
                if showDownload {
                    Button("download all", systemImage: "arrow.down.circle") { confirmingDownload = true }
                }
                if let onEdit {
                    Button("edit details", systemImage: "pencil", action: onEdit)
                }
            }
        }
    }

    private func albumCount(_ n: Int) -> String { "\(n) album\(n == 1 ? "" : "s")" }

    private func downloadTitle(count: Int) -> String {
        count > 0 ? "download \(albumCount(count))?" : "download all albums?"
    }

    private var isPlayingThisArtist: Bool {
        player.currentTrack?.artist?.id == artist.id ||
        player.currentTrack?.artist?.name == artist.name
    }
}

// MARK: - Backdrop

/// The artist page's colour: the photo blurred over the page colour, the palette gradient (violet ambient until the
/// cover colours arrive) and the scrim that keeps the bars legible. The page sets it behind the top of the hero and it scrolls away with it (`kimaHeroGround`).
struct ArtistHeroBackdrop: View {
    let coverId: String?
    let palette: CoverArtPalette?

    @Environment(AppEnvironment.self) private var env
    @State private var backdropImage: UIImage? = nil

    var body: some View {
        ZStack {
            KimaColor.base
            if let img = backdropImage {
                KimaPreblurredImage(image: img, radius: 28, zoom: 1.15)
                    .opacity(0.50)
            }
            // Richer tones when a photo already provides atmosphere; a stronger gradient when there is none.
            PaletteBackdropGradient(
                palette: palette,
                fallbackTop: KimaColor.ambient.opacity(0.35),
                fallbackMid: KimaColor.ambient.opacity(0.18),
                fallbackLow: KimaColor.base,
                topOpacity:  coverId != nil ? 0.30 : 0.40,
                midOpacity:  coverId != nil ? 0.60 : 0.80,
                lowerOpacity: 0.90,
                stop1: 0.40,
                stop2: 0.70
            )
            KimaHeroScrim()
        }
        .clipped()
        .task(id: coverId) {
            guard let id = coverId,
                  let url = CoverArtURL.url(base: env.server, coverId: id, size: 512) else {
                backdropImage = nil; return
            }
            backdropImage = try? await ImageCache.shared.fetch(url: url)
        }
    }
}
