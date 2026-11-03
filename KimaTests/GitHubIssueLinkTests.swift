import XCTest
@testable import Kima

final class GitHubIssueLinkTests: XCTestCase {
    /// A report carrying every private field the app captures, plus the ones GitHub is allowed to get.
    private func report(note: String) -> IssueReport {
        IssueReport(
            note: note, screen: "library", playbackType: "audiobook",
            nowPlayingTitle: "Secret Song Title", nowPlayingArtist: "Private Artist Name",
            positionSeconds: 61, durationSeconds: 200, isPlaying: true,
            appVersion: "0.1.0", appBuild: "10", serverHost: "music.private-host.example",
            systemVersion: "iOS 26.0", deviceModel: "iPhone17,1"
        )
    }

    private func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testLinkOpensTheRepoIssueFormWithItsFieldIDs() throws {
        let url = try XCTUnwrap(GitHubIssueLink.url(for: report(note: "the queue skipped a track")))
        XCTAssertEqual(url.host(), "github.com")
        XCTAssertEqual(url.path(), "/Chevron7Locked/kima-ios/issues/new")
        XCTAssertEqual(query(url), [
            "template": "bug_report.yml",
            "title": "the queue skipped a track",
            "what-happened": "the queue skipped a track",
            "app-version": "0.1.0 (10)",
            "ios-version": "iOS 26.0",
            "device": "iPhone17,1",
            "screen": "library",
        ])
    }

    func testNoServerAccountOrLibraryDataIsSent() throws {
        let url = try XCTUnwrap(GitHubIssueLink.url(for: report(note: "it stopped")))
        let link = url.absoluteString.removingPercentEncoding ?? ""
        for secret in ["private-host", "Secret Song", "Private Artist", "audiobook", "1:01", "3:20", "playing"] {
            XCTAssertFalse(link.contains(secret), "\(secret) leaked into the link")
        }
        let shown = GitHubIssueLink.fields(for: report(note: "it stopped")).map(\.value).joined(separator: " ")
        XCTAssertFalse(shown.contains("private-host") || shown.contains("Secret Song") || shown.contains("Private Artist"))
    }

    func testSpecialCharactersArriveAsTyped() throws {
        let note = "a & b = c + d #1? 100% café 🎧\nsecond line / done"
        let url = try XCTUnwrap(GitHubIssueLink.url(for: report(note: note)))
        let raw = url.absoluteString
        let rawQuery = String(raw[raw.index(after: try XCTUnwrap(raw.firstIndex(of: "?")))...])
        for unsafe in ["+", "#", " ", "\n", "?", "/"] {
            XCTAssertFalse(rawQuery.contains(unsafe), "\(unsafe.debugDescription) left unencoded")
        }
        XCTAssertEqual(query(url)["what-happened"], note)
        XCTAssertEqual(query(url)["title"], "a & b = c + d #1? 100% café 🎧")
    }

    func testLongNoteIsTrimmedToFitTheLink() throws {
        for unit in ["é", "🎧", "a"] {
            let note = String(repeating: unit, count: 9_000)
            let url = try XCTUnwrap(GitHubIssueLink.url(for: report(note: note)))
            XCTAssertLessThanOrEqual(url.absoluteString.count, GitHubIssueLink.maxLength)
            let sent = try XCTUnwrap(query(url)["what-happened"])
            XCTAssertTrue(sent.hasSuffix("\n\n(trimmed)"))
            let kept = sent.dropLast(GitHubIssueLink.trimmedMark.count)
            XCTAssertTrue(kept.allSatisfy { String($0) == unit }, "a character was cut in half")
            XCTAssertGreaterThan(kept.count, 100)
            // The sheet shows the same trimmed note the link sends.
            XCTAssertEqual(GitHubIssueLink.fields(for: report(note: note))[1].value, sent)
        }
    }

    func testShortNoteIsNotTrimmed() throws {
        let note = String(repeating: "word ", count: 200)
        XCTAssertEqual(query(GitHubIssueLink.url(for: report(note: note)))["what-happened"], note)
    }

    func testTitleIsTheFirstLineShortened() {
        XCTAssertEqual(GitHubIssueLink.title(for: "  skips  \nmore detail"), "skips")
        XCTAssertEqual(GitHubIssueLink.title(for: ""), "problem report")
        let long = GitHubIssueLink.title(for: String(repeating: "x", count: 200))
        XCTAssertEqual(long.count, GitHubIssueLink.titleLength)
        XCTAssertTrue(long.hasSuffix("…"))
    }

    func testEmptyFieldsAreLeftOut() throws {
        let url = GitHubIssueLink.url(for: IssueReport(note: ""))
        XCTAssertEqual(query(url), ["template": "bug_report.yml", "title": "problem report"])
    }

    func testSavedReportsFromBeforeTheDeviceFieldsStillLoad() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","capturedAt":"2026-10-01T12:00:00Z","note":"old"}]"#
        let reports = try DiagnosticsFileCodec.decoder.decode([IssueReport].self, from: Data(json.utf8))
        XCTAssertEqual(reports.first?.note, "old")
        XCTAssertNil(reports.first?.deviceModel)
    }
}
