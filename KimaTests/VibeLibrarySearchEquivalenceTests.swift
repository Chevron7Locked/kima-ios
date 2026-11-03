import XCTest
@testable import Kima

/// The byte-scan search must answer exactly like the string search it replaced. `LegacySearch` is
/// that implementation, kept here as the reference.
final class VibeLibrarySearchEquivalenceTests: XCTestCase {

    private enum LegacySearch {
        static func search(_ tracks: [VibeMapTrack], query: String, limit: Int = 8) -> VibeLibrarySearch.Matches {
            let haystacks = tracks.map { VibeLibrarySearch.fold("\($0.title) \($0.artist)") }
            let words = VibeLibrarySearch.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty, words.joined().count >= 2 else {
                return .init(query: query, ids: [], count: 0, top: [])
            }
            var ids: [String] = []
            var starts: [VibeMapTrack] = []
            var contains: [VibeMapTrack] = []
            let first = words[0]
            for (i, hay) in haystacks.enumerated() {
                guard words.allSatisfy({ hay.contains($0) }) else { continue }
                let track = tracks[i]
                ids.append(track.id)
                if hay.hasPrefix(first) || hay.contains(" " + first) {
                    if starts.count < limit { starts.append(track) }
                } else if contains.count < limit {
                    contains.append(track)
                }
            }
            return .init(query: query, ids: ids, count: Set(ids).count, top: Array((starts + contains).prefix(limit)))
        }
    }

    /// Deterministic generator so a failure reproduces.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private static let words = [
        "Blue", "monday", "Crème", "brûlée", "Beyoncé", "SIGUR", "Rós", "Ágætis", "byrjun", "Mötley", "Crüe",
        "Straße", "Ærø", "Øresund", "naïve", "café", "Ñandú", "Žižek", "Łódź", "İstanbul", "Δέλτα", "Москва",
        "東京", "ソニック", "서울", "O'Brien", "AC/DC", "P!nk", "7th", "(Live)", "–", "&", "Remix", "remastered",
        "band", "Band", "abandon", "the", "The", "of", "and", "e\u{301}cole", "Cafe\u{301}", "ﬁre", "Ⅻ", "x²",
    ]

    private func library(_ count: Int, seed: UInt64) -> [VibeMapTrack] {
        var rng = Seeded(state: seed)
        func phrase(_ n: Int) -> String {
            (0..<n).map { _ in Self.words.randomElement(using: &rng)! }.joined(separator: " ")
        }
        return (0..<count).map { i in
            VibeMapTrack(id: "t\(i)", x: 0, y: 0, title: phrase(Int.random(in: 1...4, using: &rng)),
                         artist: phrase(Int.random(in: 1...2, using: &rng)), artistId: "ar", albumId: "al",
                         coverUrl: nil, dominantMood: "happy", moodScore: 0.5, moods: [:], energy: nil, valence: nil)
        }
    }

    private func queries(_ tracks: [VibeMapTrack], seed: UInt64) -> [String] {
        var rng = Seeded(state: seed)
        var out = ["b", "  ", "", "zz", "blue monday", "BEYONCE", "creme brulee", "cafe", "ecole", "fire",
                   "straße", "strasse", "ærø", "東京", "서울", "москва", "the band", "and ", " band", "ac/dc", "p!nk"]
        for _ in 0..<300 {
            let t = tracks.randomElement(using: &rng)!
            let name = "\(t.title) \(t.artist)"
            let chars = Array(name)
            let len = Int.random(in: 1...min(8, chars.count), using: &rng)
            let start = Int.random(in: 0...(chars.count - len), using: &rng)
            var q = String(chars[start..<(start + len)])
            if Bool.random(using: &rng) { q = q.uppercased() }
            if Bool.random(using: &rng) { q += " " + Self.words.randomElement(using: &rng)!.prefix(3) }
            out.append(q)
        }
        return out
    }

    func testByteSearchAnswersExactlyLikeTheStringSearch() {
        let tracks = library(3000, seed: 7)
        let index = VibeLibraryIndex(tracks: tracks)
        for q in queries(tracks, seed: 11) {
            let new = VibeLibrarySearch.search(index, query: q)
            let old = LegacySearch.search(tracks, query: q)
            XCTAssertEqual(new.ids, old.ids, "ids differ for \"\(q)\"")
            XCTAssertEqual(new.count, old.count, "count differs for \"\(q)\"")
            XCTAssertEqual(new.top.map(\.id), old.top.map(\.id), "ranking differs for \"\(q)\"")
        }
    }

    func testTwentyThousandTracksSearchQuickly() {
        let index = VibeLibraryIndex(tracks: library(20_000, seed: 3))
        measure {
            for q in ["blue", "the band", "café", "zzz", "東京"] { _ = VibeLibrarySearch.search(index, query: q) }
        }
    }
}
