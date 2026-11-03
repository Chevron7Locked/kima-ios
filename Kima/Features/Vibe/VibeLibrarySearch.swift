import Foundation

/// Search over the tracks already loaded on the map. Instant, no server call.
/// Built once per map, off the main actor (folding 20,000 names takes tens of milliseconds).
struct VibeLibraryIndex: Sendable {
    let tracks: [VibeMapTrack]
    /// Every track's folded "title artist" as UTF-8, laid end to end; `ranges[i]` is track i's slice.
    let bytes: [UInt8]
    let ranges: [Range<Int>]

    static let empty = VibeLibraryIndex(tracks: [])

    init(tracks: [VibeMapTrack]) {
        self.tracks = tracks
        var bytes: [UInt8] = []
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(tracks.count)
        for track in tracks {
            let start = bytes.count
            bytes.append(contentsOf: VibeLibrarySearch.searchable("\(track.title) \(track.artist)").utf8)
            ranges.append(start..<bytes.count)
        }
        self.bytes = bytes
        self.ranges = ranges
    }
}

enum VibeLibrarySearch {

    struct Matches: Equatable, Sendable {
        /// The query these matches answer. The summary is built from it, so the two always agree.
        var query: String
        /// Every matching track id, in map order (these light up on the map).
        var ids: [String]
        /// How many tracks matched.
        var count: Int
        /// The best few, title-start matches first, for the result list.
        var top: [VibeMapTrack]

        static let none = Matches(query: "", ids: [], count: 0, top: [])

        static func == (a: Matches, b: Matches) -> Bool {
            a.query == b.query && a.ids == b.ids && a.top.map(\.id) == b.top.map(\.id)
        }
    }

    /// Lower-case with accents removed, so "Beyoncé" and "beyonce" meet.
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    /// `fold` in one canonical Unicode form, so names compare byte for byte.
    static func searchable(_ s: String) -> String {
        fold(s).precomposedStringWithCanonicalMapping
    }

    /// Every word of `query` must appear; accents and case are ignored. Tracks whose title or artist
    /// has a word starting with the first query word rank ahead of ones that only contain it.
    /// A query shorter than 2 letters (spaces ignored) matches nothing. Fast enough to run on
    /// every keystroke: a byte scan (`memmem`) over the index, no string work per track.
    static func search(_ index: VibeLibraryIndex, query: String, limit: Int = 8) -> Matches {
        let words = searchable(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, words.joined().count >= 2 else { return Matches(query: query, ids: [], count: 0, top: []) }

        // All needles in one buffer: each word, then " " + the first word (a word start inside the name).
        var needleBytes: [UInt8] = []
        var needles: [Range<Int>] = []
        for word in words + [" " + words[0]] {
            let start = needleBytes.count
            needleBytes.append(contentsOf: word.utf8)
            needles.append(start..<needleBytes.count)
        }
        let wordCount = words.count
        let first = needles[0], spacedFirst = needles[wordCount]

        var ids: [String] = []
        var starts: [VibeMapTrack] = []
        var contains: [VibeMapTrack] = []
        index.bytes.withUnsafeBytes { hayAll in
            needleBytes.withUnsafeBytes { needleAll in
                func has(_ hay: UnsafeRawBufferPointer, _ n: Range<Int>) -> Bool {
                    memmem(hay.baseAddress, hay.count, needleAll.baseAddress! + n.lowerBound, n.count) != nil
                }
                func hasPrefix(_ hay: UnsafeRawBufferPointer, _ n: Range<Int>) -> Bool {
                    hay.count >= n.count && memcmp(hay.baseAddress, needleAll.baseAddress! + n.lowerBound, n.count) == 0
                }
                for (i, range) in index.ranges.enumerated() {
                    let hay = UnsafeRawBufferPointer(rebasing: hayAll[range])
                    var all = true
                    for w in 0..<wordCount where !has(hay, needles[w]) { all = false; break }
                    guard all else { continue }
                    let track = index.tracks[i]
                    ids.append(track.id)
                    if hasPrefix(hay, first) || has(hay, spacedFirst) {
                        if starts.count < limit { starts.append(track) }
                    } else if contains.count < limit {
                        contains.append(track)
                    }
                }
            }
        }
        let uniqueCount = Set(ids).count
        return Matches(query: query, ids: ids, count: uniqueCount, top: Array((starts + contains).prefix(limit)))
    }

    /// The line above the results: how many matched, or that nothing did, for the query the matches
    /// answer. Nil for a query under 2 letters.
    static func summary(_ matches: Matches) -> String? {
        let trimmed = matches.query.trimmingCharacters(in: .whitespaces)
        guard fold(trimmed).replacingOccurrences(of: " ", with: "").count >= 2 else { return nil }
        if matches.count == 0 { return "no tracks match “\(trimmed)”" }
        let total = "\(matches.count.formatted()) match\(matches.count == 1 ? "" : "es")"
        if matches.count > matches.top.count { return "\(total) · showing \(matches.top.count)" }
        return total
    }

    /// True when two results would read the same: same title and same artist, from different albums.
    /// A different artist already tells them apart.
    static func collide(_ a: VibeMapTrack, _ b: VibeMapTrack) -> Bool {
        a.id != b.id && a.albumId != b.albumId
            && searchable(a.title) == searchable(b.title) && searchable(a.artist) == searchable(b.artist)
    }

    /// Albums to look up so colliding results can be told apart, each mapped to one of its tracks
    /// (the track call is the lightest one that carries the album name).
    static func albumsToName(_ tracks: [VibeMapTrack]) -> [String: String] {
        var out: [String: String] = [:]
        for t in tracks where out[t.albumId] == nil && tracks.contains(where: { collide(t, $0) }) {
            out[t.albumId] = t.id
        }
        return out
    }

    /// A result's second line: the artist, then the album when it collides with another result and
    /// that album's name is known.
    static func detail(for track: VibeMapTrack, among tracks: [VibeMapTrack], albumTitles: [String: String]) -> String {
        guard tracks.contains(where: { collide(track, $0) }), let album = albumTitles[track.albumId] else {
            return track.artist
        }
        return "\(track.artist) · \(album)"
    }
}
