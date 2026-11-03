import SwiftUI

// MARK: Hour drill — GET /stats/hour, bottom sheet

struct StatsHourSheet: View {
    let weekday: Int
    let hour: Int
    let period: StatsPeriod
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var detail: HourDetail?
    @State private var failed = false

    var body: some View {
        // Custom header, not a nested NavigationStack: a sheet-hosted stack inside the More tab
        // exposes no nav bar or done button to accessibility.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(StatsFormat.whenLabel(weekday: weekday, hour: hour))
                    .font(KimaType.pageTitle)
                    .foregroundStyle(KimaColor.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Text("done")
                        .kimaHitTarget()
                }
                .font(KimaType.headline)
                .foregroundStyle(KimaColor.textPrimary)
                .accessibilityIdentifier("hour-drill-done")
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.top, KimaSpacing.md)
            .padding(.bottom, KimaSpacing.xs)
            KimaHairline()
            contentView
        }
        // Opaque surface background, not kimaScreenCanvas: the canvas is sized to the full window,
        // so inside a narrower sheet it centers off both edges and clips the title.
        .background(KimaColor.surface)
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    private func load() async {
        failed = false
        do { detail = try await env.client.getHourDetail(weekday: weekday, hour: hour, period: period) }
        catch { failed = true }
    }

    @ViewBuilder private var contentView: some View {
        if failed {
            KimaErrorState(message: "couldn't load this hour") { Task { await load() } }
        } else if let d = detail {
            content(d)
        } else {
            KimaLoadingState { Task { await load() } }
        }
    }

    private func content(_ d: HourDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KimaSpacing.xl) {
                HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.sm) {
                    Text(d.listens.formatted(.number))
                        .font(KimaType.figure)
                        .foregroundStyle(KimaColor.textPrimary)
                        .monospacedDigit()
                    Text((d.listens == 1 ? "play" : "plays") + (d.lastAt.map { " · last played \(StatsFormat.monthYear(iso: $0))" } ?? ""))
                        .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                }
                if !d.tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("tracks").font(KimaType.caption).foregroundStyle(KimaColor.textSecondary)
                            .padding(.bottom, KimaSpacing.sm)
                        ForEach(d.tracks) { t in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                                    Text(t.title.lowercased()).font(KimaType.body)
                                        .foregroundStyle(KimaColor.textPrimary).lineLimit(1)
                                    Text(t.artist.lowercased()).font(KimaType.caption)
                                        .foregroundStyle(KimaColor.textMuted).lineLimit(1)
                                }
                                Spacer(minLength: KimaSpacing.md)
                                Text("\(t.listens)").font(KimaType.caption)
                                    .foregroundStyle(KimaColor.textSecondary).monospacedDigit()
                            }
                            .padding(.vertical, KimaSpacing.sm)
                            KimaHairline()
                        }
                    }
                }
                if !d.artists.isEmpty {
                    VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                        Text("artists").font(KimaType.caption).foregroundStyle(KimaColor.textSecondary)
                        ForEach(d.artists) { a in
                            HStack {
                                Text(a.name.lowercased()).font(KimaType.body).foregroundStyle(KimaColor.textPrimary)
                                Spacer()
                                Text("\(a.listens)").font(KimaType.caption)
                                    .foregroundStyle(KimaColor.textSecondary).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .padding(KimaSpacing.lg)
            // No kimaViewportWidth: it measures the full window, wider than this sheet, and would clip.
            // The ScrollView fills the sheet on its own.
        }
    }
}

/// One cell of the listening clock (weekday 0=mon, hour 0-23) handed to the
/// app root so the hour drill presents from where sheets publish accessibility.
struct HourDrill: Equatable, Identifiable {
    let dow: Int
    let hour: Int
    let period: StatsPeriod
    var id: Int { dow * 24 + hour }
}
