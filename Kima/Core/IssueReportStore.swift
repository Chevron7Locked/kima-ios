import Foundation
import Observation

/// On-phone log of in-app issue reports, kept as a JSON array in Documents (`issue-reports.json`) so it can be
/// pulled off the device. Reports leave the phone only when the person opens one on GitHub or exports the file.
@MainActor
@Observable
final class IssueReportStore {
    /// All reports in chronological (filing) order. The viewer displays newest-first.
    private(set) var reports: [IssueReport] = []

    init() {
        load()
        // Deletes the leftover upload-queue file; nothing reads it.
        try? FileManager.default.removeItem(at: Self.documentURL(named: "issue-report-queue.json"))
    }

    // MARK: - Persistence location

    /// `<Documents>/issue-reports.json`. Also the file shared verbatim by the Settings ShareLink.
    var exportURL: URL {
        Self.documentURL(named: "issue-reports.json")
    }

    private static func documentURL(named name: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(name)
    }

    /// True once at least one report has been filed — gates the export / clear affordances.
    var hasReports: Bool { !reports.isEmpty }

    // MARK: - Mutations

    /// Append a freshly-filed report and persist immediately.
    func append(_ report: IssueReport) {
        reports.append(report)
        save()
    }

    /// Remove every report and persist.
    func clear() {
        reports.removeAll()
        save()
    }

    // MARK: - Disk I/O

    private func load() {
        guard let data = try? Data(contentsOf: exportURL) else { return }
        reports = (try? DiagnosticsFileCodec.decoder.decode([IssueReport].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? DiagnosticsFileCodec.encoder.encode(reports) else { return }
        try? data.write(to: exportURL, options: .atomic)
    }
}

/// The on-disk JSON format of the pull-able diagnostics files: ISO-8601 dates, pretty-printed, sorted keys.
enum DiagnosticsFileCodec {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
