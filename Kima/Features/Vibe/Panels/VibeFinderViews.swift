import SwiftUI

/// What the finder found for the field being typed in: a list, "searching…", or the empty message.
/// The list is as tall as its rows up to `maxHeight`, and scrolls past that with its cut edges faded.
struct VibeFinderResults: View {
    let finder: VibeTrackFinder
    var maxHeight: CGFloat = 220
    let onPick: (VibeTrackFinder.Item) -> Void

    var body: some View {
        if !finder.items.isEmpty {
            VibeSizedScroll(maxHeight: maxHeight) {
                VStack(spacing: 0) {
                    ForEach(finder.items) { item in
                        VibeResultRow(title: item.title, detail: item.detail, id: "vibe-finder-result") { onPick(item) }
                    }
                }
            }
        } else if finder.searching {
            VibePanelNote("searching…").accessibilityIdentifier("vibe-finder-searching")
        } else if finder.empty {
            VibePanelNote("no matches").accessibilityIdentifier("vibe-finder-empty")
        }
    }
}
