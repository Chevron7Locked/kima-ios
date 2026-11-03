import SwiftUI

/// Icon-over-message card on a surface: a tinted glyph beside any content, on a rounded surface card.
struct KimaInfoCard<Content: View>: View {
    var glyph: String
    var tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: KimaSpacing.md) {
            Image(systemName: glyph).foregroundStyle(tint).font(.system(size: 18))
            content()
            Spacer(minLength: 0)
        }
        .padding(KimaSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))
    }
}

/// Inline error card: warning glyph + message on a surface card.
struct KimaErrorCard: View {
    let message: String

    var body: some View {
        KimaInfoCard(glyph: "exclamationmark.triangle.fill", tint: KimaColor.danger) {
            Text(message).font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
        }
    }
}
