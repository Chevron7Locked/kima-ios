import SwiftUI

/// The sign-in and create-account page: the ambient backdrop, a title over one line about the server, then the
/// form and its error card, in a keyboard-safe scrolling column.
struct ConnectFormPage<Content: View>: View {
    let title: String
    let subtitle: String
    let error: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            AmbientFieldBackdrop(palette: nil).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KimaSpacing.xl) {
                    VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                        Text(title)
                            .font(KimaType.pageTitle).foregroundStyle(KimaColor.textPrimary).tracking(-0.4)
                        Text(subtitle)
                            .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content()
                    if let error { KimaErrorCard(message: error) }
                    Spacer(minLength: KimaSpacing.huge)
                }
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.top, KimaSpacing.xl)
                .kimaReadableWidth()
                .frame(maxWidth: .infinity)
            }
            .kimaKeyboardSafeCanvas()
        }
    }
}
