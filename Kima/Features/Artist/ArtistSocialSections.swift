import SwiftUI

// Artist detail social sections: Available Albums, Similar Artists, Bio.
// Separated from ArtistSectionsView.swift to stay under the 350-line soft cap.
// All views here are internal (not private) so ArtistSectionsView can reference them.

// MARK: - Available Albums (unowned)

/// Shows unowned albums split into two sub-sections: studio albums and singles/EPs.
/// Download buttons fire POST /api/downloads via the ArtistDetailViewModel.
struct ArtistAvailableAlbumsSection: View {
    let albums: [Album]
    let vm: ArtistDetailViewModel
    /// Navigate to the album detail (discovery route resolves it by rgMbid): the card opens the
    /// tracklist + 30s previews, the separate Download button queues the Lidarr acquisition.
    let onTapAlbum: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: KimaSpacing.md)]

    private var studioAlbums: [Album] { albums.filter { $0.type?.lowercased() == "album" } }
    private var epsAndSingles: [Album] { albums.filter { $0.type?.lowercased() != "album" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !studioAlbums.isEmpty {
                KimaSectionHeader(title: "albums to download")
                availableGrid(for: studioAlbums)
            }
            if !epsAndSingles.isEmpty {
                KimaSectionHeader(title: "singles & eps")
                availableGrid(for: epsAndSingles)
            }
        }
    }

    @ViewBuilder
    private func availableGrid(for list: [Album]) -> some View {
        LazyVGrid(columns: columns, spacing: KimaSpacing.xl) {
            ForEach(list) { album in
                VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                    KimaCoverCard(title: album.effectiveTitle, subtitle: album.year.map(String.init), titleLines: 2,
                                  onTap: { onTapAlbum(album.id) }) {
                        CoverArtImage(coverId: album.coverArt ?? album.coverUrl, size: 256, cornerRadius: 0)
                    }

                    // Download — POST /api/downloads { type: "album", mbid: rgMbid ?? mbid }
                    if env.acquire.canAcquire {
                        Button {
                            Task { await vm.downloadAlbum(album, client: env.client, toast: toast) }
                        } label: {
                            HStack(spacing: KimaSpacing.xs) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 12))
                                Text("download")
                                    .font(KimaType.meta)
                            }
                            .foregroundStyle(KimaColor.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, KimaSpacing.xs)
                            .background(KimaColor.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
                            .kimaHitTarget(growsLayout: false)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, KimaSpacing.xs)
                    }
                }
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
    }
}

// MARK: - Similar Artists

/// Horizontal rail of similar artist cards. Routes by `artist.id` when `inLibrary`, else `artist.mbid ?? artist.id`.
/// Shows `weight * 100`% match under the name, `ownedAlbumCount` as the subtitle when present,
/// and a library badge on the corner when `inLibrary`.
struct ArtistSimilarArtistsSection: View {
    let artists: [SimilarArtist]
    let onTapArtist: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "similar artists")
            KimaRail {
                ForEach(artists) { artist in
                    SimilarArtistCard(artist: artist) {
                        // Empty mbid strings ("") must not route to an empty id — fall back to the
                        // artist's own id (same class of fix as DiscoverResult.routeId in search).
                        let navId: String
                        if artist.inLibrary == true {
                            navId = artist.id
                        } else if let m = artist.mbid, !m.isEmpty {
                            navId = m
                        } else {
                            navId = artist.id
                        }
                        onTapArtist(navId)
                    }
                    .frame(width: 96)
                }
            }
        }
    }
}

struct SimilarArtistCard: View {
    let artist: SimilarArtist
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .center, spacing: KimaSpacing.sm) {
                ZStack(alignment: .bottomTrailing) {
                    CoverArtImage(
                        coverId: artist.coverArt ?? artist.image,
                        size: 256,
                        cornerRadius: KimaRadius.image
                    )
                    .frame(width: 88, height: 88)
                    .kimaSleeveElevation(cornerRadius: KimaRadius.image)
                    .overlay(RoundedRectangle(cornerRadius: KimaRadius.image, style: .continuous).strokeBorder(KimaColor.hairline, lineWidth: 1))

                    if artist.inLibrary == true {
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(KimaColor.textSecondary)
                            .padding(KimaSpacing.xs)
                            .background(KimaColor.base, in: Circle())
                            .offset(x: 3, y: 3)
                    }
                }

                Text(artist.name.lowercased())
                    .font(KimaType.metaStrong)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 88)

                // Owned album count
                if let owned = artist.ownedAlbumCount, owned > 0 {
                    Text("\(owned) album\(owned == 1 ? "" : "s") owned")
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                        .lineLimit(1)
                        .frame(width: 88)
                }

                // Match percentage — monospaced numeral in
                // the adaptive accent, the one legitimate "emphasis" spot on this card.
                if let weight = artist.weight {
                    Text("\(Int(weight * 100))% match")
                        .font(KimaType.meta.monospacedDigit())
                        .foregroundStyle(KimaColor.brand)
                        .lineLimit(1)
                        .frame(width: 88)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bio

/// Renders the artist bio with its HTML structure (paragraphs, links) via `NSAttributedString` HTML parsing.
/// Links use the resting accent violet. The offline WebKit parse sanitizes the markup;
/// scripts and styles cannot execute.
/// Shows four lines, then "more" opens the rest in place.
struct ArtistBioSection: View {
    let bio: String
    @State private var parsed: AttributedString? = nil
    @State private var expanded = false
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private let collapsedLines = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "about")

            bioText
                .lineLimit(expanded ? nil : collapsedLines)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                // The same text unclamped, hidden, measures whether the clamp cut anything.
                .background(alignment: .top) {
                    bioText
                        .lineLimit(nil)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
                .padding(.horizontal, KimaSpacing.lg)

            if expanded || fullHeight > shownHeight + 1 {
                Button(expanded ? "less" : "more") {
                    withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
                }
                .font(KimaType.captionStrong)
                .foregroundStyle(KimaColor.textPrimary)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .padding(.horizontal, KimaSpacing.lg)
                .accessibilityLabel(expanded ? "show less of the bio" : "show the whole bio")
            }
        }
        .task(id: bio) { parsed = parseHTML(bio) }
    }

    private var bioText: some View {
        Group {
            if let attr = parsed {
                Text(attr).tint(KimaColor.textPrimary)
            } else {
                Text(bio).foregroundStyle(KimaColor.textSecondary)
            }
        }
        .font(KimaType.body)
        .foregroundStyle(KimaColor.textSecondary)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// HTML parsing via `NSAttributedString` must run on the main thread.
    /// SwiftUI `.task` closures are `@MainActor` — calling this directly is safe.
    /// Do NOT dispatch to `Task.detached`; CGImage/NSAttrStr are not thread-safe in that context.
    @MainActor
    private func parseHTML(_ html: String) -> AttributedString? {
        let wrapped = """
        <html><head><meta charset="utf-8">
        <style>
        body { font-family: -apple-system; font-size: 14px; color: #9CA3AF; line-height: 1.55; }
        a    { color: #C98F3F; text-decoration: none; }
        p    { margin: 0 0 0.75em 0; }
        </style></head><body>\(html)</body></html>
        """
        guard let data = wrapped.data(using: .utf8),
              let ns = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil)
        else { return nil }
        return (try? AttributedString(ns, including: \.uiKit)) ?? AttributedString(ns.string)
    }
}
