import SwiftUI

// MARK: - PlaylistMosaicView

/// Cover-art mosaic of `coverIds` (deduplicated, most frequent first). 0 covers shows a placeholder, 1 a full-bleed
/// image. Playlists repeat covers diagonally to fill a 2×2 grid. Mixes (`fitsCovers`) show each cover once: two side
/// by side, three as one tall and two small, four in a 2×2 grid. Needs `AppEnvironment` (for `CoverArtImage`).
struct PlaylistMosaicView: View {
    /// Up to 4 cover art IDs, sorted most-frequent first.
    let coverIds: [String]
    /// Pixel size hint sent to the cover art server for each cell.
    var cellSize: Int = 120
    /// Mix rule: fit the tile to the distinct covers. Playlist rule (false): repeat covers into a 2×2 grid.
    var fitsCovers: Bool = false
    /// Mix covers that failed to load; the tile refits without them.
    @State private var failed: Set<String> = []

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let covers = fitsCovers ? fittedCovers(excluding: failed) : coverIds
            if covers.isEmpty {
                placeholder(side: side)
            } else if fitsCovers {
                fitted(covers, side: side)
            } else if covers.count == 1 {
                singleCover(id: covers[0])
            } else {
                mosaic(side: side)
            }
        }
        // New covers start fresh: a cover that failed before may load now.
        .onChange(of: coverIds) { _, _ in failed = [] }
    }

    // MARK: - Sub-views

    private func placeholder(side: CGFloat) -> some View {
        ZStack {
            KimaColor.surface
            Image(systemName: "music.note.list")
                .font(.system(size: side * 0.28, weight: .light))
                .foregroundStyle(KimaColor.textMuted)
        }
    }

    private func singleCover(id: String) -> some View {
        CoverArtImage(coverId: id, size: cellSize * 2, cornerRadius: 0)
    }

    /// The covers laid out by `fittedFrames`: one fills, two side by side, three as one tall on the left and two
    /// small on the right, four in a 2×2 grid.
    private func fitted(_ covers: [String], side: CGFloat) -> some View {
        let frames = Self.fittedFrames(count: covers.count)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(covers, frames).enumerated()), id: \.element.0) { _, pair in
                let (id, f) = pair
                // Full-height cells ask for the larger image.
                cell(id, width: side * f.w, height: side * f.h, pixels: f.h == 1 ? cellSize * 2 : cellSize)
                    .offset(x: side * f.x, y: side * f.y)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }

    private func cell(_ id: String, width: CGFloat, height: CGFloat, pixels: Int) -> some View {
        CoverArtImage(coverId: id, size: pixels, cornerRadius: 0, fillsContainer: true,
                      onFailure: fitsCovers ? { failed.insert(id) } : nil)
            .frame(width: width, height: height)
            .clipped()
    }

    private func mosaic(side: CGFloat) -> some View {
        let cells = filledCells()
        let half = side / 2
        return LazyVGrid(
            columns: [
                GridItem(.fixed(half), spacing: 0),
                GridItem(.fixed(half), spacing: 0),
            ],
            spacing: 0
        ) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, id in
                cell(id, width: half, height: half, pixels: cellSize)
            }
        }
    }

    // MARK: - Helpers

    /// Each distinct cover once, in order, at most four, leaving out any that failed to load.
    func fittedCovers(excluding failed: Set<String> = []) -> [String] {
        var seen = Set<String>()
        return Array(coverIds.filter { !$0.isEmpty && !failed.contains($0) && seen.insert($0).inserted }.prefix(4))
    }

    /// Each fitted cell's frame as fractions of the tile's side: x, y, width, height.
    static func fittedFrames(count: Int) -> [(x: Double, y: Double, w: Double, h: Double)] {
        switch count {
        case 0: return []
        case 1: return [(0, 0, 1, 1)]
        case 2: return [(0, 0, 0.5, 1), (0.5, 0, 0.5, 1)]
        case 3: return [(0, 0, 0.5, 1), (0.5, 0, 0.5, 0.5), (0.5, 0.5, 0.5, 0.5)]
        default: return [(0, 0, 0.5, 0.5), (0.5, 0, 0.5, 0.5), (0, 0.5, 0.5, 0.5), (0.5, 0.5, 0.5, 0.5)]
        }
    }

    /// The playlist grid's four cells: 2 → [0,1,1,0], 3 → [0,1,2,0], 4+ → first 4.
    func filledCells() -> [String] {
        let c = coverIds
        switch c.count {
        case 0: return []
        case 1: return [c[0]]
        case 2: return [c[0], c[1], c[1], c[0]]
        case 3: return [c[0], c[1], c[2], c[0]]
        default: return Array(c.prefix(4))
        }
    }
}

// MARK: - Mosaic computation helper

/// Extracts frequency-sorted, deduplicated cover IDs from a list of summary items
/// (`PlaylistSummary.items`, the first 4 from the server). Returns every distinct cover, most frequent first.
func playlistMosaicCoverIds(from items: [PlaylistSummaryItem]?) -> [String] {
    guard let items, !items.isEmpty else { return [] }
    return rankedCoverIds(items.compactMap { $0.track.album?.coverUrl })
}

/// Same helper but computed from a full `PlaylistDetail.items` array.
func playlistMosaicCoverIds(from items: [PlaylistItem]?) -> [String] {
    guard let items, !items.isEmpty else { return [] }
    return rankedCoverIds(items.compactMap { $0.track.album?.coverArt })
}

/// Distinct covers ordered by how many times each appears, most frequent first; covers used equally often keep the
/// order they first appear in (as the web's `mosaicCovers`).
private func rankedCoverIds(_ covers: [String]) -> [String] {
    var counts: [String: Int] = [:]
    var order: [String] = []
    for c in covers {
        if counts[c] == nil { order.append(c) }
        counts[c, default: 0] += 1
    }
    return order.enumerated()
        .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }
        .map(\.element)
}
