import SwiftUI

// MARK: - AboutSection

/// The "about" block on book and podcast pages: a section header over the description at a readable line spacing.
struct AboutSection: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "about")
            Text(text)
                .font(KimaType.body)
                .foregroundStyle(KimaColor.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, KimaSpacing.lg)
        }
    }
}
