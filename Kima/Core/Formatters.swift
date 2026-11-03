import Foundation

// MARK: - Formatters

/// Shared date/time formatters. ISO 8601 uses `Date.ISO8601FormatStyle` because
/// `ISO8601DateFormatter` is not Sendable. Display `DateFormatter` statics are write-once and read on the main actor.
enum Formatters {

    // MARK: - ISO 8601 base formatters

    struct ISO8601Style: Sendable {
        private let style: Date.ISO8601FormatStyle
        init(_ style: Date.ISO8601FormatStyle) { self.style = style }
        func date(from string: String) -> Date? { try? style.parse(string) }
        func string(from date: Date) -> String { date.formatted(.iso8601) }
    }

    /// ISO 8601 date-time with or without fractional seconds (e.g. "2024-01-15T12:00:00.000Z").
    static let iso8601Fractional = ISO8601Style(.iso8601)

    /// Full-date ISO 8601 parser ("yyyy-MM-dd"), used for `weekStart` in Discover Weekly.
    static let iso8601FullDate = ISO8601Style(.iso8601.year().month().day())

    // MARK: - ISO 8601 helpers

    /// Parse an ISO 8601 date-time; nil when it does not parse.
    static func parseISO8601(_ string: String) -> Date? {
        iso8601Fractional.date(from: string)
    }

    /// Like `parseISO8601(_:)` but returns `.distantPast` on failure.
    /// For Codable contexts where a missing/corrupt date must not fail the whole decode.
    static func parseISO8601OrDistantPast(_ string: String) -> Date {
        parseISO8601(string) ?? .distantPast
    }

    // MARK: - Display date formatters

    /// "EEE · dd MMM" — home screen kicker date (HomeHeroView).
    static let homeShowDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE '·' dd MMM"
        return f
    }()

    /// "MMM d" — date within the current calendar year (podcast / discover).
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// "MMM d, yyyy" — date in a prior year, and discover week label.
    static let monthDayYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    /// The app's one display date, lowercase: "oct 8" within `now`'s year, "oct 8, 2025" in another year.
    static func displayDate(_ date: Date, now: Date = .now) -> String {
        let fmt = Calendar.current.isDate(date, equalTo: now, toGranularity: .year) ? monthDay : monthDayYear
        return fmt.string(from: date).lowercased()
    }

    // MARK: - Relative time

    /// "just now / Xm ago / Xh ago", then the display date.
    /// Mirrors the web `formatTime` helper. Used by activity rows (history, imports,
    /// notifications).
    static func relativeTimeString(from date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60      { return "just now" }
        if diff < 3_600   { return "\(Int(diff / 60))m ago" }
        if diff < 86_400  { return "\(Int(diff / 3_600))h ago" }
        return displayDate(date)
    }

    /// `relativeTimeString(from:)` for a server ISO-8601 timestamp; "" when it does not parse.
    static func relativeTimeString(fromISO8601 string: String) -> String {
        parseISO8601(string).map(relativeTimeString(from:)) ?? ""
    }
}
