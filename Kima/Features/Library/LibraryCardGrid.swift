import SwiftUI

/// The library's cover grid: `KimaCardGrid` in `LibraryGrid` columns.
struct LibraryCardGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        KimaCardGrid(count: items.count, minimum: LibraryGrid.minimumWidth) {
            ForEach(items) { card($0) }
        }
    }
}
