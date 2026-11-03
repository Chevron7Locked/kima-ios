import XCTest
@testable import Kima

/// Hand-written payloads. Never a real library snapshot.
final class VibeMapDecodingTests: XCTestCase {

    private func track(_ extra: String) -> String {
        """
        {"id":"t1","x":0.25,"y":0.75,"title":"a title","artist":"an artist","artistId":"ar1",
         "albumId":"al1","coverUrl":null,"dominantMood":"happy","moodScore":0.8,
         "moods":{"happy":0.8,"sad":0.1},"energy":0.6,"valence":0.7\(extra)}
        """
    }

    private func envelope(tracks: String, extra: String) -> Data {
        Data("""
        {"tracks":[\(tracks)],"trackCount":1,"computedAt":"2026-10-07T10:00:00Z"\(extra)}
        """.utf8)
    }

    private func decodeMap(_ data: Data) throws -> VibeMapResponse {
        try JSONDecoder().decode(VibeMapResponse.self, from: data)
    }

    func testTestServerShapeWithColourZAndSignature() throws {
        let r = try decodeMap(envelope(tracks: track(#","z":0.31,"colour":0.92"#),
                                       extra: #","moodSignature":"abc123""#))
        XCTAssertEqual(r.moodSignature, "abc123")
        XCTAssertEqual(r.tracks[0].colour, 0.92)
        XCTAssertEqual(r.tracks[0].z, 0.31)
        XCTAssertEqual(r.tracks[0].x, 0.25)
    }

    func testProductionShapeHasNoColourOrSignature() throws {
        let r = try decodeMap(envelope(tracks: track(#","z":0.4"#), extra: #","sampled":true"#))
        XCTAssertNil(r.tracks[0].colour)
        XCTAssertNil(r.moodSignature)
        XCTAssertEqual(r.trackCount, 1)
    }

    func testMissingZDefaultsToHalf() throws {
        let r = try decodeMap(envelope(tracks: track(""), extra: ""))
        XCTAssertEqual(r.tracks[0].z, 0.5)
        XCTAssertNil(r.tracks[0].colour)
    }

    func testMapOutcomeStillDecodesBothStates() throws {
        let ready = try JSONDecoder().decode(
            VibeMapEnvelope.self, from: envelope(tracks: track(""), extra: ""))
        guard case .ready = ready else { return XCTFail("expected ready") }
        let computing = try JSONDecoder().decode(VibeMapEnvelope.self, from: Data(#"{"computing":true}"#.utf8))
        guard case .computing = computing else { return XCTFail("expected computing") }
    }

    func testSearchBodyWithOnlyQueryAndTracksDecodes() throws {
        let body = Data("""
        {"query":"calm piano","tracks":[{"id":"t1","title":"a title","duration":200,"trackNo":1,
         "distance":0.2,"similarity":0.8,"album":{"id":"al1","title":"an album","coverUrl":null},
         "artist":{"id":"ar1","name":"an artist"}}]}
        """.utf8)
        let r = try JSONDecoder().decode(VibeSearchResponse.self, from: body)
        XCTAssertEqual(r.tracks.count, 1)
        XCTAssertEqual(r.query, "calm piano")
    }

    func testSearchBodyWithDroppedFieldsStillDecodes() throws {
        let body = Data(#"{"query":"q","tracks":[],"minSimilarity":0.4,"totalAboveThreshold":3,"debug":{}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(VibeSearchResponse.self, from: body).tracks.count, 0)
    }
}
