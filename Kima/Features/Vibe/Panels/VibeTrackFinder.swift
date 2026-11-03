import Foundation
import Observation

/// Track lookup for the song path and blend pickers: tracks on the map whose
/// title or artist match come first, then tracks whose sound matches the words (`POST /api/vibe/search`).
@MainActor
@Observable
final class VibeTrackFinder {

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let artist: String
        /// Found by how it sounds rather than by its name.
        let viaSound: Bool

        /// Second line in the list.
        var detail: String { viaSound ? "\(artist) · sounds like it" : artist }
    }

    private(set) var items: [Item] = []
    private(set) var isFetchingSound = false
    private(set) var query = ""

    var isActive: Bool { Self.isActive(query) }
    /// Nothing to show yet and the sound search is still running.
    var searching: Bool { isActive && isFetchingSound && items.isEmpty }
    /// Finished with nothing found.
    var empty: Bool { isActive && !isFetchingSound && items.isEmpty }

    /// Two or more letters, spaces ignored at the ends.
    nonisolated static func isActive(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespaces).count >= 2
    }

    /// Name matches first, then sound matches not already listed, capped at `limit`. Pure.
    nonisolated static func merge(byName: [VibeMapTrack], bySound: [VibeResultTrack], limit: Int) -> [Item] {
        var seen = Set(byName.map(\.id))
        let named = byName.map { Item(id: $0.id, title: $0.title, artist: $0.artist, viaSound: false) }
        var sound: [Item] = []
        for t in bySound where seen.insert(t.id).inserted {
            sound.append(Item(id: t.id, title: t.title, artist: t.artist.name, viaSound: true))
        }
        return Array((named + sound).prefix(limit))
    }

    /// Looks `text` up. Name matches appear at once; sound matches follow when the server answers,
    /// asked after a short pause in typing. A failed sound search leaves the name matches alone.
    /// Cancel-safe: a newer call replaces this one.
    func search(_ text: String, index: VibeLibraryIndex, client: KimaAPIClient, limit: Int = 10) async {
        let q = text.trimmingCharacters(in: .whitespaces)
        query = q
        guard Self.isActive(q) else {
            items = []
            isFetchingSound = false
            return
        }
        let byName = VibeLibrarySearch.search(index, query: q, limit: limit).top
        items = Self.merge(byName: byName, bySound: [], limit: limit)
        isFetchingSound = true
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        do {
            let resp = try await client.vibeSearch(query: q, limit: limit)
            guard !Task.isCancelled else { return }
            items = Self.merge(byName: byName, bySound: resp.tracks, limit: limit)
        } catch {
            // Sound results are a bonus; the name matches stay.
        }
        if !Task.isCancelled { isFetchingSound = false }
    }
}
