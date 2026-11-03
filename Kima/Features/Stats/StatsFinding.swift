import SwiftUI

// MARK: Shared chapter header (claim loud, note quiet, hairline under)

struct StatsFinding: View {
    let claim: String
    var note: String? = nil
    /// Names the period a shelf section is about, for sections the period
    /// control does not reach.
    var scope: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(claim)
                    .font(KimaType.figure)
                    .foregroundStyle(KimaColor.textPrimary)
                    .tracking(-0.4)
                    .fixedSize(horizontal: false, vertical: true)
                if let scope {
                    Text(scope)
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                }
                Spacer(minLength: KimaSpacing.md)
            }
            if let note {
                Text(note)
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            KimaHairline()
        }
    }
}
