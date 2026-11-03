import SwiftUI

// Cover, metadata and action bar; the page pins AlbumHeroBackdrop (the cover's colours) behind it.
// Action bar lives in AlbumActionBar.swift.

// MARK: - Hero view

struct AlbumHeroView: View {
    let album: Album
    let isOwned: Bool
    let vm: AlbumDetailViewModel
    let onTapArtist: (String) -> Void
    /// Opens the metadata editor from the action row's menu; nil for albums not in the library.
    var onEdit: (() -> Void)? = nil
    /// Top safe-area inset (status bar + nav bar), passed from AlbumDetailView. The atmospheric
    /// backdrop bleeds to the true screen top (the ScrollView ignores the top safe area); this
    /// pushes only the CONTENT down so the cover/title clear the notch — "gradient fills the whole
    /// top, only the content stops for the notch."
    var topSafeArea: CGFloat = 0

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast

    @State private var showCoverViewer = false

    private var coverId: String? { Self.coverId(for: album) }

    /// The album's own cover if it has one, else the library's.
    static func coverId(for album: Album) -> String? { album.userCoverUrl ?? album.coverArt ?? album.coverUrl }

    /// True when any track from THIS album is the active playing track.
    private var isThisAlbumPlaying: Bool {
        guard player.isPlaying, let current = player.currentTrack else { return false }
        let ids = Set((album.tracks ?? []).map { $0.id })
        return ids.contains(current.id)
    }

    var body: some View {
        // The page draws the cover-colour backdrop (AlbumHeroBackdrop) behind the hero at its height.
        VStack(alignment: .leading, spacing: 0) {
            heroInfo

            AlbumActionBarView(
                album: album,
                isOwned: isOwned,
                isThisAlbumPlaying: isThisAlbumPlaying,
                vm: vm,
                onEdit: onEdit
            )
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.bottom, KimaSpacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Tap the cover → open it full-screen (owned bool; presenter dismisses via onClose).
        .fullScreenCover(isPresented: $showCoverViewer) {
            CoverImageViewer(
                coverId: coverId,
                size: 1024,
                title: album.effectiveTitle,
                subtitle: album.artist?.name,
                onClose: { showCoverViewer = false }
            )
            .appEnvironment(env, toast)
        }
    }

    // MARK: - Hero info (cover art + metadata)

    private var heroInfo: some View {
        KimaDetailHero(topInset: topSafeArea) {
            CoverArtImage(coverId: coverId, size: 512, cornerRadius: KimaRadius.hero)
                .contentShape(Rectangle())
                .onTapGesture { showCoverViewer = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("opens the cover full screen")
        } info: {
            KimaKicker(title: "album")
            titleRow
            artistButton
            metadataText
            genreTag
        }
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: KimaSpacing.sm) {
            KimaDetailHeroTitle(text: album.effectiveTitle)

            if album.hasUserOverrides == true {
                KimaTag(text: "edited", tone: .strong).padding(.top, KimaSpacing.xs)
            }
        }
    }

    @ViewBuilder
    private var artistButton: some View {
        if let artist = album.artist {
            Button {
                if let id = artist.id { onTapArtist(id) }
            } label: {
                KimaDetailHeroByline(text: artist.name ?? "")
            }
            .buttonStyle(.plain)
            .disabled(artist.id == nil)
        }
    }

    private var metadataText: some View {
        KimaDetailHeroMeta(parts: metadataParts)
    }

    @ViewBuilder
    private var genreTag: some View {
        if let genre = album.userGenres?.first ?? album.genres?.first ?? album.genre {
            KimaTag(text: genre.lowercased())
        }
    }

    // True when the displayed title already holds the year ("Alive 2007"); the metadata line
    // then skips it, so the year shows once.
    private func titleContainsYear(_ year: Int) -> Bool {
        album.effectiveTitle.lowercased().contains(String(year))
    }

    private var metadataParts: [String] {
        var parts: [String] = []
        if let yr = album.displayYear ?? album.year, !titleContainsYear(yr) { parts.append(String(yr)) }
        if let n = album.trackCount ?? album.songCount {
            parts.append("\(n) song\(n == 1 ? "" : "s")")
        }
        if let dur = album.duration, dur > 0 { parts.append(dur.durationFormatted) }
        return parts
    }
}

// MARK: - Backdrop

/// The album page's cover colour: the cover blurred and darkened, the palette gradient over it, and the scrim that
/// keeps the bars legible. The page sets it behind the top of the hero and it scrolls away with it (`kimaHeroGround`).
struct AlbumHeroBackdrop: View {
    let coverId: String?

    @Environment(AppEnvironment.self) private var env
    @State private var palette: CoverArtPalette? = nil

    var body: some View {
        KimaCoverColourBackdrop(coverId: coverId, palette: palette, topOpacity: 0.30, midOpacity: 0.60, scrim: true)
            .task(id: coverId) {
                palette = await CoverArtColor.palette(coverId: coverId, server: env.server)
            }
    }
}
