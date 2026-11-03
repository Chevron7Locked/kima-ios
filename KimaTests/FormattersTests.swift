import XCTest
@testable import Kima

final class FormattersTests: XCTestCase {
    func testParseISO8601() {
        let expected = Date(timeIntervalSince1970: 1_705_320_000)
        XCTAssertEqual(Formatters.parseISO8601("2024-01-15T12:00:00.000Z"), expected)
        XCTAssertEqual(Formatters.parseISO8601("2024-01-15T12:00:00Z"), expected)
        XCTAssertNotNil(Formatters.parseISO8601("2024-01-15T12:00:00.123456Z"))
        XCTAssertNil(Formatters.parseISO8601("2024-01-15"))
        XCTAssertNotNil(Formatters.iso8601FullDate.date(from: "2024-01-15"))
    }

    func testRelativeTimeString() {
        XCTAssertEqual(Formatters.relativeTimeString(from: Date()), "just now")
        XCTAssertEqual(Formatters.relativeTimeString(from: Date().addingTimeInterval(-120)), "2m ago")
        XCTAssertEqual(Formatters.relativeTimeString(from: Date().addingTimeInterval(-7200)), "2h ago")
    }

    func testDisplayDateIsLowercaseWithTheYearOnlyWhenItDiffers() {
        let now = Formatters.parseISO8601("2026-10-09T12:00:00Z")!
        let sameYear = Formatters.parseISO8601("2026-03-12T12:00:00Z")!
        let lastYear = Formatters.parseISO8601("2025-01-05T12:00:00Z")!
        XCTAssertEqual(Formatters.displayDate(sameYear, now: now), Formatters.monthDay.string(from: sameYear).lowercased())
        XCTAssertEqual(Formatters.displayDate(lastYear, now: now), Formatters.monthDayYear.string(from: lastYear).lowercased())
        XCTAssertEqual(Formatters.displayDate(lastYear, now: now), Formatters.displayDate(lastYear, now: now).lowercased())
        XCTAssertTrue(Formatters.displayDate(lastYear, now: now).contains("2025"))
        XCTAssertFalse(Formatters.displayDate(sameYear, now: now).contains("2026"))
    }

    func testRelativeTimeStringFromISO8601() {
        XCTAssertEqual(Formatters.relativeTimeString(fromISO8601: "not a date"), "")
        let date = Date().addingTimeInterval(-7200)
        let iso = ISO8601DateFormatter().string(from: date)
        XCTAssertEqual(Formatters.relativeTimeString(fromISO8601: iso),
                       Formatters.relativeTimeString(from: Formatters.parseISO8601(iso)!))
    }

    func testDurationFormatted() {
        XCTAssertEqual(0.0.durationFormatted, "0:00")
        XCTAssertEqual(59.4.durationFormatted, "0:59")
        XCTAssertEqual(59.6.durationFormatted, "1:00")
        XCTAssertEqual(119.6.durationFormatted, "2:00")
        XCTAssertEqual(3599.6.durationFormatted, "1:00:00")
        XCTAssertEqual(3600.0.durationFormatted, "1:00:00")
        XCTAssertEqual(3661.0.durationFormatted, "1:01:01")
        XCTAssertEqual(3725.0.durationFormatted, "1:02:05")
    }

    func testDurationFormattedBadInputs() {
        XCTAssertEqual((-5.0).durationFormatted, "0:00")
        XCTAssertEqual(Double.nan.durationFormatted, "0:00")
        XCTAssertEqual(Double.infinity.durationFormatted, "0:00")
        XCTAssertEqual((-Double.infinity).durationFormatted, "0:00")
        _ = Double.greatestFiniteMagnitude.durationFormatted
    }

    func testStatsClockRounds() {
        XCTAssertEqual(StatsFormat.clock(119.6), "2:00")
    }

    /// Episode and book lengths read as lengths, never as a clock time.
    func testLengthLabel() {
        XCTAssertEqual((18 * 60 + 31.0).lengthLabel, "18m")
        XCTAssertEqual((3600 + 4 * 60.0).lengthLabel, "1h 4m")
        XCTAssertEqual(20.0.lengthLabel, "<1m")
        XCTAssertEqual(Double.nan.lengthLabel, "<1m")
    }

    func testEpisodeDatesAreLowercase() {
        let text = "2024-06-14T12:00:00Z".podcastDateDisplay
        XCTAssertEqual(text, text.lowercased())
        XCTAssertTrue(text.hasPrefix("jun 14"), text)
    }
}
