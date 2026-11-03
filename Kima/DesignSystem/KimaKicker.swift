import SwiftUI

// MARK: - KimaKicker

/// Kicker over a title or a section ("album", "this week's pick"): a 6pt dot beside a muted meta-role
/// caption. The dot is faint unless the caller tints it. 6pt matches the web hero's eyebrow dot (EntityHero).
struct KimaKicker: View {
    let title: String
    var dotColor: Color = KimaColor.textFaint

    var body: some View {
        HStack(spacing: KimaSpacing.xs) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(title)
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
                .tracking(0.1)
        }
    }
}
