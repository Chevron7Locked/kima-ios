import SwiftUI

// MARK: - The play-history audit (false starts)
//
// Plays recorded before 1.10.1 include tracks skipped while loading. The only evidence is the gap to the next
// play: a short gap proves a skip, a long one proves nothing, so only provable false starts are raised.

struct StatsFalseStarts: View {
    @Environment(AppEnvironment.self) private var env

    @State private var audit: FalseStartAudit?
    @State var picked: Set<String> = []
    @State var busy = false
    @State private var arming = false
    @State private var note: String?
    @State private var error: String?
    @State var showIgnored = false
    @State private var elapsed = 0
    @State var page = 0

    static let maxPerAction = 2000   // the server's per-action track cap
    static let rowsPerPage = 20

    enum AuditAction: String, Identifiable {
        case collapse, remove, ignore, restore
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            StatsFinding(claim: "play history cleanup", note: nil)

            VStack(alignment: .leading, spacing: KimaSpacing.xl) {
                if audit == nil { intro }
                if let a = audit { results(a) }

                if let note { Text(note).font(KimaType.body).foregroundStyle(KimaColor.textPrimary) }
                if let error { Text(error).font(KimaType.caption).foregroundStyle(KimaColor.danger) }
            }
        }
        // Remove is the web's two-stage arm (below); collapse goes through a confirmation. It presents from the
        // app root (router.statsConfirm -> StatsConfirmSheet), not a `.confirmationDialog` here: a dialog
        // presented inside a tab's NavigationStack publishes no accessibility elements. The sheet's title
        // states the consequence.
    }

    /// Hand a confirmation to the app root. The closure captures this view's
    /// @State storage, so it runs against current picked/audit state.
    private func requestConfirm(_ kind: StatsConfirm.Kind) {
        guard let audit else { return }
        env.router.statsConfirm = StatsConfirm(kind: kind, count: kind == .collapse ? audit.collapsibleRows : pickedStarts(audit)) { [self] k in
            switch k {
            case .collapse:
                act(.collapse, ids: []) { r in "merged \(r.removed.formatted(.number)) \(r.removed == 1 ? "duplicate" : "duplicates")" }
            case .remove:
                act(.remove, ids: Array(picked)) { r in
                    "removed \(r.removed.formatted(.number)) \(r.removed == 1 ? "record" : "records") from \(r.tracks.formatted(.number)) \(r.tracks == 1 ? "track" : "tracks")"
                }
            }
        }
    }

    // MARK: Intro (pre-audit)

    private var intro: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.lg) {
            Text("finds plays logged for tracks you skipped, recorded before version 1.10.1")
                .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
            auditButton(busy ? "scanning…" : "scan play history") { load() }
                .accessibilityIdentifier("audit-scan")
            if busy && elapsed >= 3 {
                Text("scanning · \(elapsed)s")
                    .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ a: FalseStartAudit) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  alignment: .leading, spacing: KimaSpacing.lg) {
            Figure(n: a.skipped, label: "skipped (removable)")
            Figure(n: a.heard, label: "confirmed")
            Figure(n: a.unclear, label: "unclear (kept)")
            if a.tooShort > 0 { Figure(n: a.tooShort, label: "track too short to count") }
            Figure(n: a.totalListens, label: "total plays")
        }

        if a.collapsibleRows > 0 {
            VStack(alignment: .leading, spacing: KimaSpacing.md) {
                Text(mergeParagraph(a))
                    .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                auditButton(a.collapsibleRows == 1 ? "merge 1 duplicate" : "merge \(a.collapsibleRows.formatted(.number)) duplicates") {
                    requestConfirm(.collapse)
                }
                .accessibilityIdentifier("audit-merge")
            }
        }

        let listing = showIgnored ? a.ignored.count : a.tracks.count
        if listing == 0 && !showIgnored {
            HStack(spacing: KimaSpacing.sm) {
                Text("nothing to review")
                    .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                if !a.ignored.isEmpty {
                    Button("show \(a.ignored.count.formatted(.number)) ignored") { toggleIgnored() }
                        .font(KimaType.headline).foregroundStyle(KimaColor.textSecondary)
                        .buttonStyle(.plain)
                }
            }
        }
        if listing > 0 {
            list(a)
        }
        if !a.ignored.isEmpty && listing > 0 {
            Button(showIgnored ? "back to results" : "show \(a.ignored.count.formatted(.number)) ignored") { toggleIgnored() }
                .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                .buttonStyle(.plain)
        }

        if !picked.isEmpty && !showIgnored { consequence(a) }
    }

    @ViewBuilder
    private func consequence(_ a: FalseStartAudit) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            Text("remove deletes the skipped plays and can't be undone · ignore keeps all plays and stops flagging the track · music files are never touched")
                .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
            HStack(spacing: KimaSpacing.md) {
                Button {
                    if arming { requestConfirm(.remove) } else { arming = true }
                } label: {
                    Text(arming
                         ? "delete \(pickedStarts(a).formatted(.number)) \(pickedStarts(a) == 1 ? "play" : "plays")?"
                         : "remove skipped plays (\(picked.count.formatted(.number)) \(picked.count == 1 ? "track" : "tracks"))")
                        .font(KimaType.headline)
                        .foregroundStyle(KimaColor.textPrimary)
                        .padding(.horizontal, KimaSpacing.lg).padding(.vertical, KimaSpacing.md)
                        .background(arming ? KimaColor.dangerFill : KimaColor.surfaceRaised,
                                    in: RoundedRectangle(cornerRadius: KimaRadius.card))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityIdentifier("audit-remove")
                if arming {
                    Button("cancel") { arming = false }
                        .font(KimaType.headline).foregroundStyle(KimaColor.textMuted)
                        .buttonStyle(.plain)
                }
                Button("ignore") {
                    act(.ignore, ids: Array(picked)) { r in
                        "ignored \(r.ignored.formatted(.number)) \(r.ignored == 1 ? "track" : "tracks")"
                    }
                }
                .font(KimaType.headline).foregroundStyle(KimaColor.textSecondary)
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityIdentifier("audit-ignore")
            }
        }
    }

    // MARK: Actions

    private func mergeParagraph(_ a: FalseStartAudit) -> String {
        let dup = a.duplicateRows == 1
            ? "1 is a duplicate written mid-track"
            : "\(a.duplicateRows.formatted(.number)) are duplicates written mid-track"
        let rows = "\(a.totalRows.formatted(.number)) \(a.totalRows == 1 ? "record" : "records")"
        let plays = "\(a.totalListens.formatted(.number)) \(a.totalListens == 1 ? "play" : "plays")"
        return "\(rows) for \(plays) · \(dup) · merging changes no play counts"
    }

    func listing(_ a: FalseStartAudit) -> Int { showIgnored ? a.ignored.count : a.tracks.count }

    func pickedStarts(_ a: FalseStartAudit) -> Int {
        a.tracks.filter { picked.contains($0.trackId) }.map(\.skipped).reduce(0, +)
    }

    private func toggleIgnored() { showIgnored.toggle(); page = 0 }

    /// The web's quiet ghost button (bg-white/[0.06]) as used by the audit's
    /// run-on-demand actions — same shape as the intro's, no brand fill.
    private func auditButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: KimaSpacing.sm) {
                if busy { ProgressView().controlSize(.small).tint(KimaColor.brand) }
                Text(title).font(KimaType.headline).foregroundStyle(KimaColor.textPrimary)
            }
            .padding(.horizontal, KimaSpacing.lg).padding(.vertical, KimaSpacing.md)
            .background(KimaColor.surfaceRaised, in: RoundedRectangle(cornerRadius: KimaRadius.card))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func load() {
        busy = true
        error = nil
        elapsed = 0
        // No invented progress bar: the scan is one pass over an entire history
        // with no honest fraction, so it says what it is doing and, once the
        // silence is long enough to worry about, how long for (web parity).
        Task {
            let started = Date()
            let ticker = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    elapsed = Int(Date().timeIntervalSince(started))
                }
            }
            defer { ticker.cancel(); busy = false }
            do {
                audit = try await env.client.getFalseStartAudit()
                picked = []
                page = 0
                arming = false
            } catch {
                self.error = "couldn't load play history"
            }
        }
    }

    func act(_ action: AuditAction, ids: [String], said: @escaping (StatsCountsResponse) -> String) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let r: StatsCountsResponse
                switch action {
                case .collapse: r = try await env.client.collapseDuplicatePlayRows()
                case .remove:   r = try await env.client.removeFalseStarts(trackIds: ids)
                case .ignore:   r = try await env.client.ignoreFalseStartTracks(trackIds: ids)
                case .restore:  r = try await env.client.unignoreFalseStartTracks(trackIds: ids)
                }
                note = said(r)
                picked = []
                arming = false
                showIgnored = false
                audit = try await env.client.getFalseStartAudit()
            } catch {
                self.error = "failed · nothing changed"
            }
        }
    }

    private struct Figure: View {
        let n: Int
        let label: String
        var body: some View {
            VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                Text(n.formatted(.number))
                    .font(KimaType.figure)
                    .foregroundStyle(KimaColor.textPrimary)
                    .monospacedDigit()
                Text(label).font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
