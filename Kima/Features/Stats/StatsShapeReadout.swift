import SwiftUI

// MARK: Readout under the brightness and energy plot

struct StatsShapeReadout: View {
    enum Content {
        case idle(headline: String, body: String?, meta: [String])
        case loading
        case region(RegionDetail)
    }

    let content: Content
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            switch content {
            case let .idle(headline, body, meta):
                Text(headline)
                    .font(KimaType.figure)
                    .foregroundStyle(KimaColor.textPrimary)
                if let body {
                    Text(body).font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                }
                ForEach(meta, id: \.self) { line in
                    Text(line).font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                }
            case .loading:
                HStack {
                    ProgressView().controlSize(.small).tint(KimaColor.brand)
                    Spacer()
                    clearButton
                }
            case let .region(r):
                HStack(alignment: .firstTextBaseline) {
                    Text("\(StatsShapeMath.energyWord(r.energy ?? 0.5)), \(StatsShapeMath.brightnessWord(r.valence ?? 0.5))")
                        .font(KimaType.figure)
                        .foregroundStyle(KimaColor.textPrimary)
                    Spacer()
                    clearButton
                }
                Text("\(r.listens.formatted(.number)) \(r.listens == 1 ? "play" : "plays") here"
                     + (r.bpm.map { " · avg \(Int($0.rounded())) bpm" } ?? ""))
                    .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                ForEach(Array(r.tracks.prefix(5))) { t in
                    HStack(alignment: .firstTextBaseline) {
                        Text(t.title.lowercased()).foregroundStyle(KimaColor.textPrimary)
                            + Text(" · \(t.artist.lowercased())").foregroundStyle(KimaColor.textSecondary)
                        Spacer(minLength: KimaSpacing.md)
                        Text("\(t.listens)")
                            .font(KimaType.caption).foregroundStyle(KimaColor.textMuted).monospacedDigit()
                    }
                    .font(KimaType.body)
                    .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shape-readout")
    }

    private var clearButton: some View {
        KimaCloseButton(label: "clear", id: "shape-readout-clear", action: onClear)
    }
}
