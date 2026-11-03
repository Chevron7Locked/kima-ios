import SwiftUI

// MARK: - KimaTag

/// The one small label chip: "edited", "owned", "soon", a genre, a play count, a section's source.
/// One size (the meta role), one padding, a hairline edge. `strong` is for state that matters ("edited", "soon",
/// "owned"): ink text and a brighter edge, no amber.
struct KimaTag: View {
    enum Tone { case neutral, strong }

    let text: String
    var icon: String? = nil
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: KimaSpacing.xs) {
            if let icon { Image(systemName: icon).font(.system(size: 8, weight: .semibold)) }
            Text(text).monospacedDigit()
        }
        .font(KimaType.meta)
        .foregroundStyle(foreground)
        .lineLimit(1)
        .padding(.horizontal, KimaSpacing.sm)
        .padding(.vertical, KimaSpacing.xs)
        .background(fill, in: Capsule())
        .overlay { Capsule().strokeBorder(tone == .strong ? KimaColor.hairlineStrong : KimaColor.hairline, lineWidth: 1) }
        .fixedSize()
    }

    private var foreground: Color { tone == .strong ? KimaColor.textPrimary : KimaColor.textMuted }
    private var fill: Color { KimaColor.fillQuiet }
}

// MARK: - KimaCountBadge

/// The unread count, amber like the web bell's dot. Over `dotAbove` it shrinks to a dot; otherwise the number,
/// capped at `cap`.
struct KimaCountBadge: View {
    let count: Int
    var dotAbove: Int = .max
    var cap: Int = 99

    var body: some View {
        if count > dotAbove {
            Circle().fill(KimaColor.brand).frame(width: 8, height: 8)
        } else {
            Text("\(min(count, cap))")
                .font(KimaType.meta.monospacedDigit())
                .foregroundStyle(KimaColor.onBrand)
                .padding(.horizontal, 5)  // fixed geometry: a 16pt count badge
                .frame(minWidth: 16, minHeight: 16)
                .background(KimaColor.brand, in: Capsule())
        }
    }
}

// MARK: - KimaStatTile

/// One number over its label, on a quiet tile (import preview, release radar).
struct KimaStatTile: View {
    let value: String
    let label: String
    var tint: Color = KimaColor.textPrimary

    var body: some View {
        VStack(spacing: KimaSpacing.xs) {
            Text(value)
                .font(KimaType.figure)
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(KimaSpacing.md)
        .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))
        .overlay(RoundedRectangle(cornerRadius: KimaRadius.card).strokeBorder(KimaColor.hairline, lineWidth: 1))
    }
}
