import SwiftUI

/// Issue reports: lists filed reports newest-first, exports `issue-reports.json` through
/// ShareLink, and clears all after confirming. Pushed from Settings > About.
struct IssueReportsView: View {
    @Environment(AppEnvironment.self) private var env

    private var store: IssueReportStore { env.issueReports }

    var body: some View {
        ZStack {
            KimaScreenGround()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    KimaScreenHeader(title: "issue reports")

                    if store.hasReports {
                        // Hairline-separated rows on the gutter, then "clear all" alone at the end.
                        VStack(spacing: 0) {
                            ForEach(store.reports.reversed()) { report in
                                reportRow(report)
                                KimaHairline()
                            }
                        }
                        .padding(.horizontal, KimaSpacing.lg)
                        .padding(.top, KimaSpacing.sm)
                        KimaDestructiveRow(
                            label: "clear all reports",
                            confirmTitle: "clear all reports?",
                            confirmMessage: "deletes all reports on this device. exported copies aren't affected.",
                            confirmButton: "clear all reports"
                        ) { store.clear() }
                    } else {
                        emptyState
                    }
                }
                .kimaReadableWidth()
                .frame(maxWidth: .infinity)
            }
            .kimaScrollTopGround()
            .kimaMiniPlayerClearance()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.hasReports {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: store.exportURL) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(KimaColor.textPrimary)
                    }
                    .accessibilityLabel("export reports")
                }
            }
        }
    }

    // MARK: - Report row

    private func reportRow(_ report: IssueReport) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            Text(report.capturedTimeString)
                .font(KimaType.captionStrong)
                .foregroundStyle(KimaColor.textSecondary)

            Text(report.note.isEmpty ? "no note" : report.note)
                .font(KimaType.body)
                .foregroundStyle(report.note.isEmpty ? KimaColor.textMuted : KimaColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(report.contextLine)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, KimaSpacing.lg)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        KimaEmptyState(icon: "exclamationmark.bubble", title: "no reports yet",
                       message: "use report a problem in the more tab to log one.")
    }
}
