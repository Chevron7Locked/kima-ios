import SwiftUI

/// A tool on the vibe map's right edge: a 44pt hairline ring with no fill (the size of the top bar's
/// discs) and a small label under it, both at full strength. Amber only while the tool is on. The label
/// stops growing at the default text size so it fits the rail; larger sizes get the large content
/// viewer (touch and hold) instead.
struct VibeInstrumentButton: View {
    let symbol: String
    let label: String
    let id: String
    var on = false
    /// What VoiceOver says, when it should say more than the label.
    var spokenLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: KimaSpacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .kimaOutlineRing(on: on)
                Text(label)
                    .font(KimaType.meta)
                    .tracking(0.6)
                    .lineLimit(1)
                    .fixedSize()
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }
            .foregroundStyle(on ? KimaColor.brand : KimaColor.textPrimary)
            .shadow(color: KimaColor.base, radius: 3, y: 1)
            .frame(minWidth: KimaLayout.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.kimaCard)
        .accessibilityShowsLargeContentViewer {
            Image(systemName: symbol)
            Text(label)
        }
        .accessibilityLabel(spokenLabel ?? label)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
