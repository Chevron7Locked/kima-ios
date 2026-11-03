import SwiftUI

// MARK: - DiscoverTierIndicator
//
// Subtle match-tier signal: a small colored dot, plus a short mono label at full size. The same
// color ramp is used wherever a DiscoverTrack's tier appears (featured pick, featured rows, crate tail).

struct DiscoverTierIndicator: View {
    let tier: DiscoverTier
    /// `true` → dot only, sized for the dense crate tail. `false` (default) → dot + label,
    /// for the featured pick and featured rows where there's room to spell it out.
    var compact: Bool = false

    /// Color ramp by tier: high is positive (green, strong match), medium is caution (amber),
    /// explore/low is textMuted (low confidence), wildcard/wild is the violet ambient (out-of-pattern).
    private var color: Color {
        switch tier {
        case .high:             return KimaColor.positive
        case .medium:           return KimaColor.caution
        case .explore, .low:    return KimaColor.textMuted
        case .wildcard, .wild:  return KimaColor.ambient
        }
    }

    private var shortLabel: String {
        tier.label.split(separator: " ").first.map(String.init) ?? tier.label
    }

    var body: some View {
        HStack(spacing: KimaSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)

            if !compact {
                Text(shortLabel)
                    .font(KimaType.meta)
                    .foregroundStyle(color.opacity(0.85))
                    .tracking(0.1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tier.label)
    }
}
