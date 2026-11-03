import SwiftUI

extension StatsFalseStarts {
    @ViewBuilder
    func list(_ a: FalseStartAudit) -> some View {
        let all = a.tracks.map(\.trackId)
        let selectable = min(all.count, Self.maxPerAction)
        let allPicked = selectable > 0 && picked.count == selectable
        let pages = max(1, (listing(a) + Self.rowsPerPage - 1) / Self.rowsPerPage)
        let at = min(page, pages - 1)
        let from = at * Self.rowsPerPage

        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                if showIgnored {
                    Text("\(a.ignored.count.formatted(.number)) ignored")
                        .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                } else {
                    HStack {
                        Button(allPicked ? "select none" : "select all \(selectable.formatted(.number))") {
                            picked = allPicked ? [] : Set(all.prefix(Self.maxPerAction))
                        }
                        .font(KimaType.headline).foregroundStyle(KimaColor.textSecondary)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("audit-select-all")
                        Spacer()
                    }
                    Text(headerCaption(a))
                        .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, KimaSpacing.sm)

            if showIgnored {
                ForEach(a.ignored.sliceWindow(from, Self.rowsPerPage)) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                            Text(t.title.lowercased()).font(KimaType.body)
                                .foregroundStyle(KimaColor.textSecondary).lineLimit(1)
                            Text(t.artist.lowercased()).font(KimaType.caption)
                                .foregroundStyle(KimaColor.textMuted).lineLimit(1)
                        }
                        Spacer()
                        Button("restore") {
                            act(.restore, ids: [t.trackId]) { _ in "restored" }
                        }
                        .font(KimaType.headline).foregroundStyle(KimaColor.textSecondary)
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                    .padding(.vertical, KimaSpacing.md)
                    KimaHairline()
                }
            } else {
                ForEach(a.tracks.sliceWindow(from, Self.rowsPerPage)) { t in
                    let on = picked.contains(t.trackId)
                    Button {
                        if on { picked.remove(t.trackId) } else { picked.insert(t.trackId) }
                    } label: {
                        HStack(alignment: .top, spacing: KimaSpacing.md) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(on ? KimaColor.brand : KimaColor.textFaint)
                            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                                Text(t.title.lowercased()).font(KimaType.body)
                                    .foregroundStyle(KimaColor.textPrimary).lineLimit(1)
                                Text(t.artist.lowercased()).font(KimaType.caption)
                                    .foregroundStyle(KimaColor.textMuted).lineLimit(1)
                                counts(t)
                                    .font(KimaType.caption).monospacedDigit().lineLimit(1)
                                Text(rule(t)).font(KimaType.caption).foregroundStyle(KimaColor.textFaint).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .padding(.vertical, KimaSpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("audit-row-\(t.trackId)")
                    KimaHairline()
                }
            }

            if pages > 1 {
                HStack {
                    Spacer()
                    Text("\(from + 1)–\(min(from + Self.rowsPerPage, listing(a))) of \(listing(a).formatted(.number))")
                        .font(KimaType.caption).foregroundStyle(KimaColor.textMuted).monospacedDigit()
                    Button { page = max(0, at - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(at == 0)
                    Button { page = at + 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(at >= pages - 1)
                }
                .font(KimaType.headline).foregroundStyle(KimaColor.textSecondary)
                .buttonStyle(.plain)
                .padding(.top, KimaSpacing.sm)
            }
        }
    }

    private func headerCaption(_ a: FalseStartAudit) -> String {
        if picked.isEmpty {
            return "\(a.tracks.count.formatted(.number)) \(a.tracks.count == 1 ? "track" : "tracks") with skipped plays"
        }
        let plays = pickedStarts(a)
        return "\(picked.count.formatted(.number)) selected · \(plays.formatted(.number)) \(plays == 1 ? "play" : "plays") to remove"
    }

    private func counts(_ t: FalseStartTrack) -> Text {
        let plays = "\(t.listens.formatted(.number)) \(t.listens == 1 ? "play" : "plays")"
        let confirmed = t.heard > 0 ? " · \(t.heard.formatted(.number)) confirmed" : ""
        return Text("\(t.skipped.formatted(.number)) skipped").foregroundStyle(KimaColor.textMuted)
            + Text(" · \(plays)\(confirmed)").foregroundStyle(KimaColor.textMuted)
    }

    private func rule(_ t: FalseStartTrack) -> String {
        guard let required = t.requiredSeconds else {
            return "\(StatsFormat.clock(t.durationSeconds)) long · too short to count"
        }
        guard let shortest = t.shortestRunSeconds else {
            return "counts after \(StatsFormat.clock(required))"
        }
        return "shortest \(StatsFormat.clock(shortest)) · counts after \(StatsFormat.clock(required))"
    }

}

extension Array {
    func sliceWindow(_ from: Int, _ size: Int) -> [Element] {
        guard from < self.count else { return [] }
        return Array(self.prefix(from + size).dropFirst(from))
    }
}

