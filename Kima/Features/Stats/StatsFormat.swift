import Foundation

// MARK: - Numbers as a person would say them
//
// Time derived from track length is introduced with "about"; time from a real playback position never is.
// Nothing rounds to a lie: 0.4 hours is "24 minutes", not "0 hours".

enum StatsFormat {
    /// Just the figure, for when a label already says what it is.
    static func hours(_ seconds: Double) -> String {
        let h = seconds / 3600
        if h < 10 && h > 0 { return String(format: "%.1f", h) }
        return Int(h.rounded()).formatted(.number)
    }

    /// "9pm" — one hour of the day, said the way a person says it.
    static func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour < 12 ? "am" : "pm")"
    }

    /// "thursday 9pm".
    static func whenLabel(weekday: Int, hour: Int) -> String {
        "\(weekdayName(weekday)) \(hourLabel(hour))"
    }

    static func weekdayName(_ weekday: Int) -> String {
        (0..<7).contains(weekday)
            ? ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][weekday]
            : ""
    }

    static func percent(part: Int, whole: Int) -> Int {
        whole <= 0 ? 0 : Int(Double(part) / Double(whole) * 100.0 + 0.5)
    }

    /// "m:ss" — the audit's clock for durations.
    static func clock(_ seconds: Double) -> String {
        seconds.durationFormatted
    }

    static func monthYear(iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) ?? fractionalDate(iso) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: d).lowercased()
    }

    /// iOS ISO8601DateFormatter is strict; server timestamps carry fractions.
    private static func fractionalDate(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return f.date(from: iso)
    }
}
