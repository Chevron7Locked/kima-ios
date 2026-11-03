import SwiftUI

/// Launch-time gate when a remembered session exists but the server can't be reached (address
/// changed, server offline). Offers Retry and Change server address, neither needing the server.
struct ServerUnreachableView: View {
    let host: String
    /// Set when the server answered with an error instead of not answering at all.
    var serverError: String? = nil
    /// Re-runs `SessionStore.resume()`. On success the phase flips to `.authenticated` and this view
    /// is torn down; on continued failure it returns here.
    var onRetry: () async -> Void
    var onChangeServer: () -> Void

    @State private var isRetrying = false

    var body: some View {
        ZStack {
            KimaColor.base.ignoresSafeArea()

            VStack(spacing: KimaSpacing.xl) {
                Spacer()

                KimaMark()
                    .frame(width: 44, height: 44)
                    .opacity(0.9)
                    .accessibilityHidden(true)

                VStack(spacing: KimaSpacing.sm) {
                    Text(serverError == nil ? "can't reach your server" : "your server answered with an error")
                        .font(KimaType.pageTitle)
                        .foregroundStyle(KimaColor.textPrimary)
                        .tracking(-0.4)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Text(host)
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.top, KimaSpacing.xs)

                    Text(serverError.map { "\($0) retry, or change the address." }
                         ?? "it may be offline or at a new address. retry, or change the address.")
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, KimaSpacing.xs)
                }

                Spacer()

                VStack(spacing: KimaSpacing.md) {
                    KimaPrimaryButton(
                        title: isRetrying ? "retrying…" : "retry",
                        isLoading: isRetrying,
                        systemImage: "arrow.clockwise"
                    ) {
                        guard !isRetrying else { return }
                        isRetrying = true
                        Task { await onRetry(); isRetrying = false }
                    }

                    Button(action: onChangeServer) {
                        Text("change server address")
                            .font(KimaType.headline)
                            .foregroundStyle(KimaColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, KimaSpacing.md)
                            .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, KimaSpacing.xxl)
            }
            .padding(.horizontal, KimaSpacing.lg)
            .kimaReadableWidth()
        }
    }
}

#Preview {
    ServerUnreachableView(host: "kima.example.com", onRetry: {}, onChangeServer: {})
        .preferredColorScheme(.dark)
}
