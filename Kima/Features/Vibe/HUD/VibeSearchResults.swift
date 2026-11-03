import SwiftUI

/// The list under the top search box: how many tracks matched and the first eight, on the map's dark
/// fade (no box). The caller sets the room on its right. Tapping one selects it and flies the camera there;
/// nothing plays. Results that share a title show their album once its name is known. When the keyboard
/// leaves too little room the list scrolls, faded at the cut edge.
struct VibeSearchResults: View {
    let matches: VibeLibrarySearch.Matches
    /// Album id → name, for telling same-title results apart.
    let albumTitles: [String: String]
    /// Screen y the list must end above (the keyboard's top); nil when nothing covers the screen.
    let bottomLimit: CGFloat?
    let onPick: (VibeMapTrack) -> Void

    @State private var listTop: CGFloat = 0

    private var maxHeight: CGFloat {
        guard let bottomLimit else { return .infinity }
        return max(bottomLimit - listTop - KimaSpacing.sm, KimaLayout.minTouchTarget * 2)
    }

    var body: some View {
        if let summary = VibeLibrarySearch.summary(matches) {
            VStack(alignment: .leading, spacing: 0) {
                Text(summary)
                    .font(KimaType.meta)
                    .monospacedDigit()
                    .foregroundStyle(KimaColor.textMuted)
                    .padding(.vertical, KimaSpacing.sm)
                    .accessibilityIdentifier("vibe-search-summary")
                if !matches.top.isEmpty {
                    // A set height: the list hangs below the top row and must not shrink to fit it.
                    VibeSizedScroll(maxHeight: maxHeight, exact: true) {
                        VStack(spacing: 0) {
                            ForEach(matches.top) { track in
                                VibeResultRow(title: track.title,
                                              detail: VibeLibrarySearch.detail(for: track, among: matches.top,
                                                                               albumTitles: albumTitles),
                                              id: "vibe-search-result") { onPick(track) }
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { listTop = $0 }
                }
            }
            .padding(.leading, KimaSpacing.lg)
            .padding(.bottom, KimaSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
