import SwiftUI

/// One track in a vibe search list (top search, song path and blend finders): title over a second line,
/// flush with the list's edge. Rows are set apart by space, not lines.
struct VibeResultRow: View {
    let title: String
    let detail: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VibeTitleDetail(title: title, detail: detail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, KimaSpacing.xs)
                .frame(minHeight: KimaLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// A track's title over its second line (artist, album or how it was found), both lowercase, one line each.
struct VibeTitleDetail: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.xs) {
            Text(title.lowercased())
                .font(KimaType.body)
                .foregroundStyle(KimaColor.textPrimary)
                .lineLimit(1)
            Text(detail.lowercased())
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
                .lineLimit(1)
        }
    }
}

/// A picked track in a panel, on one line: an optional small label ("start", "selected"), the title,
/// the artist after it in grey, then the row's control (a × that removes it). The title gives way when
/// the line is full and the artist stays; the text stops growing at the largest standard size.
struct VibePickRow<Trailing: View>: View {
    var label: String? = nil
    var labelWidth: CGFloat = 34
    let pick: VibeTrackPick
    let id: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            if let label {
                Text(label)
                    .font(KimaType.meta)
                    .tracking(0.6)
                    .foregroundStyle(KimaColor.textMuted)
                    .fixedSize()
                    .frame(minWidth: labelWidth, alignment: .leading)
            }
            VibeTitleArtistLayout {
                Text(pick.title.lowercased())
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(1)
                Text(pick.artist.lowercased())
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing().fixedSize()
        }
        .frame(minHeight: KimaLayout.minTouchTarget)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

/// A title then an artist on one line, on a shared baseline. When they don't fit, the title gives way
/// first while the artist keeps its width, until the title is down to half the line; past that both
/// shorten.
struct VibeTitleArtistLayout: Layout {
    var spacing: CGFloat = KimaSpacing.sm

    /// The widths the two get on a line `available` wide, given the widths they want. Pure.
    static func widths(title: CGFloat, artist: CGFloat, available: CGFloat,
                       spacing: CGFloat) -> (title: CGFloat, artist: CGFloat) {
        let room = max(available - spacing, 0)
        let artistWidth = max(min(artist, room - min(title, room / 2)), 0)
        return (min(title, room - artistWidth), artistWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(proposal.width, subviews)?.size ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let frames = place(bounds.width, subviews)?.frames else { return }
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(frame.size))
        }
    }

    /// Each view's frame inside the line, and the line's size.
    private func place(_ width: CGFloat?, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize)? {
        guard subviews.count == 2 else { return nil }
        let wanted = subviews.map { $0.sizeThatFits(.unspecified).width }
        let available = width ?? (wanted[0] + spacing + wanted[1])
        let w = Self.widths(title: wanted[0], artist: wanted[1], available: available, spacing: spacing)
        let dims = [subviews[0].dimensions(in: ProposedViewSize(width: w.title, height: nil)),
                    subviews[1].dimensions(in: ProposedViewSize(width: w.artist, height: nil))]
        let baseline = dims.map { $0[VerticalAlignment.firstTextBaseline] }.max() ?? 0
        let frames = [
            CGRect(x: 0, y: baseline - dims[0][VerticalAlignment.firstTextBaseline], width: w.title, height: dims[0].height),
            CGRect(x: w.title + spacing, y: baseline - dims[1][VerticalAlignment.firstTextBaseline],
                   width: w.artist, height: dims[1].height),
        ]
        return (frames, CGSize(width: frames[1].maxX, height: frames.map(\.maxY).max() ?? 0))
    }
}
