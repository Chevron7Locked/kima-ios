import XCTest
@testable import Kima

/// Preview resolution on the artist page (ticket 14): the row asks the session's `StreamSource`
/// for a clip answer — minting and URL assembly are invisible here — and only when there is no
/// answer does the payload's raw Deezer link serve, because it expires ~27 h after the server
/// fetched the playlist. Seam: `ArtistDetailViewModel.previewURL(track:artistName:stream:)` over
/// a stubbed client; everything observed as requests recorded by the stub transport.
@MainActor
final class ArtistPreviewFallbackTests: XCTestCase {
    let server = KimaServer(baseURL: URL(string: "https://stub.test")!)

    override func tearDown() { StubURLProtocol.reset() }

    private func makeTrack(previewUrl: String?) -> Track {
        Track(id: "t1", title: "Voulez Vous", duration: 30, previewUrl: previewUrl)
    }

    func testTicketedServerAnswersTheProxyUrlNotTheRawLink() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"ticket":"st-9","expiresIn":3600}"#.utf8)) }
        let stream = StreamSource(server: server, client: .stubbed(credential: .jwt("SECRET.LOGIN.JWT")))

        let url = await ArtistDetailViewModel().previewURL(
            track: makeTrack(previewUrl: "https://cdn.test/raw.mp3"),
            artistName: "ABBA", stream: stream)

        // This seam pins only the policy choice — server proxy over raw CDN link. The wire shape
        // (encoded path, ticket query) is pinned once at the source interface in StreamSourceTests.
        XCTAssertTrue(url?.path.hasPrefix("/api/artists/preview/") ?? false,
                      "expected the server's preview proxy, got \(url?.absoluteString ?? "nothing")")
    }

    /// A mint that fails is not a reason to leak the login token or dead-end the row: the raw
    /// Deezer link plays instead (the established no-ticket fallback).
    func testNoTicketFallsBackToTheRawPreviewLink() async {
        StubURLProtocol.handler = { _ in (500, Data()) }
        let stream = StreamSource(server: server, client: .stubbed(credential: .jwt("SECRET.LOGIN.JWT")))

        let url = await ArtistDetailViewModel().previewURL(
            track: makeTrack(previewUrl: "https://cdn.test/raw.mp3"),
            artistName: "ABBA", stream: stream)

        XCTAssertEqual(url?.absoluteString, "https://cdn.test/raw.mp3")
    }

    func testNoTicketAndNoRawLinkAnswersNothing() async {
        StubURLProtocol.handler = { _ in (500, Data()) }
        let stream = StreamSource(server: server, client: .stubbed(credential: .jwt("SECRET.LOGIN.JWT")))

        let url = await ArtistDetailViewModel().previewURL(
            track: makeTrack(previewUrl: nil), artistName: "ABBA", stream: stream)

        XCTAssertNil(url)
    }
}
