import XCTest
@testable import Kima

@MainActor
final class MetadataUpdateDiffTests: XCTestCase {
    private let base = FormSnapshot(nameOrTitle: "Name", bio: "Bio", genres: "a, b",
                                    mbidOrRgMbid: "mb", imageUrl: "http://x/y.png", year: "1999", trackNo: "3")

    func testUnchangedSendsNothing() throws {
        let a = MetadataEditorViewModel.artistUpdate(from: base, to: base)
        XCTAssertNil(a.name); XCTAssertNil(a.bio); XCTAssertNil(a.genres); XCTAssertNil(a.mbid); XCTAssertNil(a.heroUrl)
        let al = try MetadataEditorViewModel.albumUpdate(from: base, to: base)
        XCTAssertNil(al.title); XCTAssertNil(al.year); XCTAssertNil(al.genres)
        let t = try MetadataEditorViewModel.trackUpdate(from: base, to: base)
        XCTAssertNil(t.title); XCTAssertNil(t.trackNo)
        XCTAssertTrue(try json(a).isEmpty)
    }

    func testOnlyBioEditedSetsOnlyBio() {
        var b = base; b.bio = "New bio"
        let u = MetadataEditorViewModel.artistUpdate(from: base, to: b)
        XCTAssertEqual(u.bio, .set("New bio"))
        XCTAssertNil(u.name); XCTAssertNil(u.genres); XCTAssertNil(u.mbid); XCTAssertNil(u.heroUrl)
    }

    func testGenreWhitespaceOnlyChangeIsNoChange() {
        var b = base; b.genres = "a,b"
        XCTAssertNil(MetadataEditorViewModel.artistUpdate(from: base, to: b).genres)
    }

    func testClearingTextFieldSendsNull() throws {
        var b = base; b.bio = "  "; b.imageUrl = ""
        let u = MetadataEditorViewModel.artistUpdate(from: base, to: b)
        XCTAssertEqual(u.bio, .clear)
        let body = try json(u)
        XCTAssertEqual(Set(body.keys), ["bio", "heroUrl"])
        XCTAssertTrue(body["bio"] is NSNull)
        XCTAssertTrue(body["heroUrl"] is NSNull)
    }

    func testClearingGenresSendsEmptyList() throws {
        var b = base; b.genres = ""
        let body = try json(try MetadataEditorViewModel.albumUpdate(from: base, to: b))
        XCTAssertEqual(body["genres"] as? [String], [])
    }

    func testClearingYearAndTrackNumberSendsNull() throws {
        var b = base; b.year = ""; b.trackNo = ""
        XCTAssertTrue(try json(try MetadataEditorViewModel.albumUpdate(from: base, to: b))["year"] is NSNull)
        XCTAssertTrue(try json(try MetadataEditorViewModel.trackUpdate(from: base, to: b))["trackNo"] is NSNull)
    }

    func testClearingMusicBrainzIdIsNoChange() {
        var b = base; b.mbidOrRgMbid = ""
        XCTAssertNil(MetadataEditorViewModel.artistUpdate(from: base, to: b).mbid)
    }

    func testBadYearThrows() {
        var b = base; b.year = "abc"
        XCTAssertThrowsError(try MetadataEditorViewModel.albumUpdate(from: base, to: b)) {
            XCTAssertEqual($0 as? MetadataInputError, .year)
        }
    }

    func testYearAndTrackNumberParse() throws {
        var b = base; b.year = "2001"; b.trackNo = "7"
        XCTAssertEqual(try MetadataEditorViewModel.albumUpdate(from: base, to: b).year, .set(2001))
        XCTAssertEqual(try MetadataEditorViewModel.trackUpdate(from: base, to: b).trackNo, .set(7))
    }

    func testSaveWithNoChangesSendsNothing() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        let album = try JSONDecoder().decode(Album.self, from: Data(#"{"id":"al1","title":"t"}"#.utf8))
        let vm = MetadataEditorViewModel(kind: .album(album))
        let sent = try await vm.save(client: .stubbed())
        XCTAssertFalse(sent)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
