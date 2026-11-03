import Foundation

/// GitHub's new-issue page for the app, prefilled from a report through the repo's `bug_report.yml` issue form
/// (each query key is a field id there). It carries only the note, app version, OS version, device model and
/// screen; never the server, account or what was playing.
enum GitHubIssueLink {
    static let newIssuePage = "https://github.com/Chevron7Locked/kima-ios/issues/new"
    static let template = "bug_report.yml"
    /// GitHub refuses over-long links (414), so the note is cut to keep the whole link under this.
    static let maxLength = 7_000
    static let trimmedMark = "\n\n(trimmed)"
    static let titleLength = 70

    struct Field: Equatable {
        /// The query key: the issue form's field id, or `title`.
        let id: String
        /// The name the report sheet shows.
        let label: String
        let value: String
    }

    /// The prefilled fields in form order, with the note already cut to fit.
    static func fields(for report: IssueReport) -> [Field] {
        let version = [report.appVersion, report.appBuild.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        var fields = [
            Field(id: "title", label: "title", value: title(for: report.note)),
            Field(id: "what-happened", label: "what happened", value: ""),
            Field(id: "app-version", label: "app", value: version),
            Field(id: "ios-version", label: "ios", value: report.systemVersion ?? ""),
            Field(id: "device", label: "device", value: report.deviceModel ?? ""),
            Field(id: "screen", label: "screen", value: report.screen ?? ""),
        ]
        let room = maxLength - link(for: fields).count
        fields[1] = Field(id: "what-happened", label: "what happened", value: fitted(report.note, room: room))
        return fields
    }

    static func url(for report: IssueReport) -> URL? {
        URL(string: link(for: fields(for: report)))
    }

    /// The note's first line, shortened; a generic title when the note is empty.
    static func title(for note: String) -> String {
        let line = note.split(whereSeparator: \.isNewline).first.map {
            $0.trimmingCharacters(in: .whitespaces)
        } ?? ""
        if line.isEmpty { return "problem report" }
        return line.count > titleLength ? String(line.prefix(titleLength - 1)) + "…" : line
    }

    // MARK: - Encoding

    private static func link(for fields: [Field]) -> String {
        let pairs = [("template", template)] + fields.filter { !$0.value.isEmpty }.map { ($0.id, $0.value) }
        return newIssuePage + "?" + pairs.map { "\($0.0)=\(encoded($0.1))" }.joined(separator: "&")
    }

    /// `note` as is when its encoded form fits in `room` (counting the `&what-happened=` it adds), otherwise its
    /// longest whole-character prefix that fits with the trimmed mark.
    private static func fitted(_ note: String, room: Int) -> String {
        let budget = room - "&what-happened=".count
        if encoded(note).count <= budget { return note }
        var left = budget - encoded(trimmedMark).count
        var kept = ""
        for character in note {
            let cost = encoded(String(character)).count
            guard cost <= left else { break }
            kept.append(character)
            left -= cost
        }
        return kept + trimmedMark
    }

    /// Percent-encodes everything but RFC 3986 unreserved characters, so `+`, `&`, `=` and `#` survive as text.
    private static func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private static let unreserved = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )
}
