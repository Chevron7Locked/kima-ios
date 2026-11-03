import XCTest
@testable import Kima

/// The release-window payload as the server actually writes it: a release
/// note the window opens on, one-line summaries beside the list, and the run-from-window action named by
/// its `run` field. These are the shapes the window's whole layout depends on.
final class WhatsNewModelsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testReleaseCarriesTheMaintainersNote() throws {
        let r = try decode(WhatsNewRelease.self, #"""
        {"version":"1.11.0","title":"Kima 1.11","summary":"s","date":"2026-10-05",
         "note":{"from":"Kevin","body":"Hey y'all.\n\nI know updates have been slow."},
         "items":[{"kind":"note","key":"vibe.engine","title":"The new vibe engine",
                  "summary":"Songs now match on how they sound.","body":"Kima used to match songs on sound alone."}]}
        """#)
        XCTAssertEqual(r.note?.from, "Kevin")
        XCTAssertTrue(r.note?.body.contains("updates have been slow") ?? false)
        XCTAssertEqual(r.shortVersion, "1.11")
        XCTAssertEqual(r.items.first?.summary, "Songs now match on how they sound.")
    }

    func testReleaseWithoutNoteDecodesNarrow() throws {
        // The server synthesises this shape for a retired mood mix waiting for an answer.
        let r = try decode(WhatsNewRelease.self, #"""
        {"version":"1.11.0","title":"One thing left from 1.11","summary":"s","date":"2026-10-05",
         "items":[{"kind":"action","key":"moods.mixes.retired","title":"Your old mood mix",
                  "summary":"Its mood no longer exists.","body":"b","cta":"Save as playlist"}]}
        """#)
        XCTAssertNil(r.note)
        XCTAssertEqual(r.items.count, 1)
    }

    func testNoteMissingItsSignatureStillShowsItsBody() throws {
        let r = try decode(WhatsNewRelease.self, #"""
        {"version":"1.0.0","title":"t","summary":"s","date":"d",
         "note":{"body":"The body survives a missing signature."},"items":[]}
        """#)
        XCTAssertEqual(r.note?.from, "kima")
        XCTAssertEqual(r.note?.body, "The body survives a missing signature.")
    }

    func testItemWithoutSummaryFallsBackToItsBody() throws {
        let item = try decode(WhatsNewItem.self,
                              #"{"kind":"note","key":"k","title":"t","body":"The body is the line."}"#)
        XCTAssertEqual(item.summary, "The body is the line.")
    }

    /// The regression this exists for: the server names the job (`run:"wipeEnrichment"`) and has never
    /// sent a `runsFromWindow` flag. iOS read the flag, so the 1.11 wipe action never appeared.
    func testWipeActionRunsFromTheWindow() throws {
        let item = try decode(WhatsNewItem.self, #"""
        {"kind":"action","key":"engine.wipe","title":"Wipe and re-run enrichment","summary":"s","body":"b",
         "cta":"Wipe and re-run","run":"wipeEnrichment",
         "confirmTitle":"Wipe and re-run enrichment?","confirmLabel":"Wipe and re-run",
         "ifClosed":"If you close now, nothing is wiped."}
        """#)
        XCTAssertEqual(item.run, "wipeEnrichment")
        XCTAssertTrue(item.runsFromWindow,
                      "the wipe action must run from the window; the server says so in `run`")
        XCTAssertFalse(item.title.isEmpty)
    }

    func testActionWithoutRunDoesNotOfferToRun() throws {
        let item = try decode(WhatsNewItem.self,
            #"{"kind":"action","key":"plays.repair","title":"t","summary":"s","body":"b"}"#)
        XCTAssertNil(item.run)
        XCTAssertFalse(item.runsFromWindow)
    }

    func testUnknownKindStillDecodesAsNote() throws {
        let item = try decode(WhatsNewItem.self,
            #"{"kind":"telepathy","key":"k","title":"t","summary":"s","body":"b"}"#)
        XCTAssertEqual(item.kind, .note)
    }
}
