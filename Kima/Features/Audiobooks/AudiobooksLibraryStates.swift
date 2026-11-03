import SwiftUI

// MARK: - AudiobooksLibraryView empty / error states
//
// Extension methods on the view so they share its namespace without touching @State.
// Both use the shared state views so every screen's empty/error reads the same.

extension AudiobooksLibraryView {

    var notConfiguredView: some View {
        KimaEmptyState(
            icon: "book.closed.fill",
            title: "audiobooks aren't set up",
            message: "set up Audiobookshelf in kima's web settings to see your audiobooks."
        )
    }

    func errorView(_ message: String, onRetry: @escaping () -> Void) -> some View {
        KimaErrorState(message: message, onRetry: onRetry)
    }
}
