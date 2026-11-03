import SwiftUI

/// One 16pt semibold glyph on the glass chrome disc — the app's top-bar button chrome.
/// `cardStyle` gives the pressable card feedback (the vibe map's toolbar); plain (default) is
/// a bare tap target (sheet closes).
struct KimaChromeButton: View {
    let symbol: String
    let label: String
    let id: String
    var cardStyle = false
    let action: () -> Void

    var body: some View {
        if cardStyle {
            Button(action: action) { glyph }
                .buttonStyle(.kimaCard)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        } else {
            Button(action: action) { glyph }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(KimaColor.textPrimary)
            .kimaChromeDisc()
    }
}

/// The "×" that closes or removes something. `.inline` (a panel, a help line, a picked track, a row):
/// a 12pt muted glyph centred in a 44pt tap area, with no disc. `.screen` (a sheet or a full-screen
/// view): a 16pt glyph on the glass chrome disc, like the map's exit.
struct KimaCloseButton: View {
    enum Kind { case inline, screen }

    let label: String
    let id: String
    var kind: Kind = .inline
    let action: () -> Void

    var body: some View {
        switch kind {
        case .inline:
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KimaColor.textMuted)
                    .frame(width: KimaLayout.minTouchTarget, height: KimaLayout.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
        case .screen:
            KimaChromeButton(symbol: "xmark", label: label, id: id, action: action)
        }
    }
}
