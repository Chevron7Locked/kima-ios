import SwiftUI

// MARK: - Loading

/// Centered spinner shown while a query is in flight. After `slowAfter` it adds "server is slow
/// to answer" and, when the screen passes `onRetry`, a "try again" button — a hung server would
/// otherwise spin for a minute before the request times out.
struct KimaLoadingState: View {
    var text = "loading…"
    var onRetry: (() -> Void)? = nil

    static let slowAfter: Duration = .seconds(10)

    @State private var isSlow = false
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: KimaSpacing.lg) {
            Spacer()
            HStack(spacing: KimaSpacing.md) {
                ProgressView().tint(KimaColor.brand)
                Text(text)
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textMuted)
            }
            if isSlow {
                VStack(spacing: KimaSpacing.md) {
                    Text("server is slow to answer")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                    if let onRetry {
                        Button {
                            attempt += 1
                            onRetry()
                        } label: {
                            Text("try again")
                                .font(KimaType.headline)
                                .foregroundStyle(KimaColor.textSecondary)
                                .padding(.horizontal, KimaSpacing.xl)
                                .padding(.vertical, KimaSpacing.md)
                                .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            }
            Spacer()
        }
        // Restarts on each retry, so the hint comes back only if the new attempt is slow too.
        .task(id: attempt) {
            isSlow = false
            try? await Task.sleep(for: Self.slowAfter)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { isSlow = true }
        }
    }
}

// MARK: - Error

/// Error card + a quiet "try again" (web PageState: the retry is not the amber primary).
struct KimaErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: KimaSpacing.xl) {
            Spacer()
            VStack(spacing: KimaSpacing.lg) {
                KimaErrorCard(message: message)

                KimaPrimaryButton(title: "try again", style: .secondary, action: onRetry)
            }
            .padding(.horizontal, KimaSpacing.xl)
            Spacer()
        }
    }
}

// MARK: - Empty

/// Empty-state shown when a tab returns zero items.
struct KimaEmptyState: View {
    var icon: String = "music.note"
    var title: String = "your library is empty"
    var message: String? = "add music on your server to see it here."

    var body: some View {
        VStack(spacing: KimaSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(KimaColor.textMuted)
            Text(title)
                .font(KimaType.headline)
                .foregroundStyle(KimaColor.textPrimary)
            if let message {
                Text(message)
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(KimaSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
