import SwiftUI

/// The rows of a page-sized list. Up to `eagerLimit` rows are built in one go when the list appears, so scrolling
/// builds nothing; a lazy stack builds each row as it scrolls in, which drops frames on every row. Longer lists stay
/// lazy, where building every row at once would hold up the page as it opens.
struct KimaPageStack<Content: View>: View {
    /// The most rows (or grid cards) built in one go.
    static var eagerLimit: Int { 80 }

    let count: Int
    var alignment: HorizontalAlignment = .center
    /// Builds every row in one go whatever the count, for a list whose rows must all stay alive (a row being dragged).
    var allEager = false
    @ViewBuilder let content: () -> Content

    @State private var grown = EagerGrowth()

    var body: some View {
        Group {
            if allEager || grown.eager(count) {
                VStack(alignment: alignment, spacing: 0, content: content)
            } else {
                LazyVStack(alignment: alignment, spacing: 0, content: content)
            }
        }
        .onChange(of: count, initial: true) { _, new in grown.update(new) }
    }
}

/// Keeps a list that opened short built in one go as more pages are added to it, up to three times
/// `KimaPageStack.eagerLimit`: swapping to a lazy stack mid-scroll would rebuild every row and could move the page.
/// Emptying the list (a new search or reload) starts over.
struct EagerGrowth {
    private var opened = false

    func eager(_ count: Int) -> Bool {
        let limit = KimaPageStack<EmptyView>.eagerLimit
        return count <= limit || (opened && count <= limit * 3)
    }

    mutating func update(_ count: Int) {
        if count == 0 { opened = false }
        else if count <= KimaPageStack<EmptyView>.eagerLimit { opened = true }
    }
}

/// A grid of cards in `GridItem(.adaptive(minimum:maximum:))` columns. Up to `KimaPageStack.eagerLimit` cards are
/// built in one go (`KimaAdaptiveGrid`), and a grid that opened that short stays so as pages are added (`EagerGrowth`);
/// a longer grid stays lazy.
struct KimaCardGrid<Content: View>: View {
    let count: Int
    var minimum: CGFloat = 155
    var maximum: CGFloat = .infinity
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat = KimaSpacing.md
    var rowSpacing: CGFloat = KimaSpacing.xl
    @ViewBuilder let content: () -> Content

    @State private var grown = EagerGrowth()

    var body: some View {
        Group {
            if grown.eager(count) {
                KimaAdaptiveGrid(minimum: minimum, maximum: maximum, spacing: spacing, rowSpacing: rowSpacing) { content() }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: spacing)],
                          alignment: alignment, spacing: rowSpacing, content: content)
            }
        }
        .onChange(of: count, initial: true) { _, new in grown.update(new) }
    }
}

/// The columns of `GridItem(.adaptive(minimum:maximum:))`, built at once for a short grid: as many equal columns of at
/// least `minimum` as fit, no wider than `maximum` and centred as a group, each item centred vertically in its row, rows
/// as tall as their tallest item.
struct KimaAdaptiveGrid: Layout {
    var minimum: CGFloat = 155
    var maximum: CGFloat = .infinity
    let spacing: CGFloat
    let rowSpacing: CGFloat

    private func columns(for width: CGFloat) -> (count: Int, width: CGFloat) {
        let count = max(1, Int((width + spacing) / (minimum + spacing)))
        return (count, min(maximum, (width - spacing * CGFloat(count - 1)) / CGFloat(count)))
    }

    private func rowHeights(_ subviews: Subviews, count: Int, columnWidth: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: count).map { start in
            subviews[start..<min(start + count, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
                .max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimum
        let (count, columnWidth) = columns(for: width)
        let rows = rowHeights(subviews, count: count, columnWidth: columnWidth)
        return CGSize(width: width, height: rows.reduce(0, +) + rowSpacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (count, columnWidth) = columns(for: bounds.width)
        let rows = rowHeights(subviews, count: count, columnWidth: columnWidth)
        let used = CGFloat(count) * columnWidth + spacing * CGFloat(count - 1)
        let left = bounds.minX + max(0, bounds.width - used) / 2
        var y = bounds.minY
        for (row, height) in rows.enumerated() {
            for column in 0..<count {
                let index = row * count + column
                guard index < subviews.count else { break }
                let x = left + CGFloat(column) * (columnWidth + spacing) + columnWidth / 2
                subviews[index].place(at: CGPoint(x: x, y: y + height / 2), anchor: .center,
                                      proposal: ProposedViewSize(width: columnWidth, height: nil))
            }
            y += height + rowSpacing
        }
    }
}
