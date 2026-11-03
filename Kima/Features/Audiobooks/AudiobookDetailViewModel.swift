import Foundation
import Observation

// MARK: - AudiobookDetailViewModel

@MainActor
@Observable
final class AudiobookDetailViewModel {

    var audiobook: Audiobook? = nil
    var isLoading = false
    var errorMessage: String? = nil
    var palette: CoverArtPalette? = nil
    var isResettingProgress = false
    var isMarkingComplete   = false

    // MARK: - Fetch

    func load(id: String, client: KimaAPIClient) async {
        guard !isLoading else { return }
        isLoading    = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            audiobook = try await client.getAudiobook(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchPalette(server: KimaServer) async {
        guard let coverId = audiobook?.coverUrl else { return }
        palette = await CoverArtColor.palette(coverId: coverId, server: server)
    }

    // MARK: - Actions

    /// Reset all progress for the book ("reset progress" or "listen again"). Returns the progress it
    /// replaced, for undo.
    @discardableResult
    func resetProgress(client: KimaAPIClient) async throws -> AudiobookProgress? {
        guard let book = audiobook else { return nil }
        isResettingProgress = true
        defer { isResettingProgress = false }
        audiobook = book.withProgress(nil)
        do {
            try await client.deleteAudiobookProgress(bookId: book.id)
            return book.progress
        } catch {
            audiobook = book
            throw error
        }
    }

    /// Mark the book as 100% complete: `currentTime == duration`, `isFinished == true`. Returns the progress
    /// it replaced, for undo.
    @discardableResult
    func markComplete(client: KimaAPIClient) async throws -> AudiobookProgress? {
        guard let book = audiobook else { return nil }
        isMarkingComplete = true
        defer { isMarkingComplete = false }
        audiobook = book.withProgress(AudiobookProgress(currentTime: book.duration, progress: 100.0, isFinished: true))
        do {
            try await client.saveAudiobookProgress(
                bookId: book.id,
                currentTime: book.duration,
                duration: book.duration,
                isFinished: true
            )
            return book.progress
        } catch {
            audiobook = book
            throw error
        }
    }

    /// Undo for reset and mark as finished: saves `previous` again, or clears progress when there was none.
    func restoreProgress(_ previous: AudiobookProgress?, client: KimaAPIClient) async throws {
        guard let book = audiobook else { return }
        audiobook = book.withProgress(previous)
        do {
            if let previous {
                try await client.saveAudiobookProgress(
                    bookId: book.id, currentTime: previous.currentTime,
                    duration: book.duration, isFinished: previous.isFinished)
            } else {
                try await client.deleteAudiobookProgress(bookId: book.id)
            }
        } catch {
            audiobook = book
            throw error
        }
    }

    // MARK: - Computed display helpers

    /// Stored progress fraction (0–1). Used when the player is not playing this book.
    var storedProgressFraction: Double {
        guard let book = audiobook else { return 0 }
        let p = book.progress?.progress ?? 0
        return min(max(p / 100, 0), 1)
    }

    /// Sections to display. Empty when no sections or when count > 50.
    var displaySections: [AudiobookSection] {
        guard let secs = audiobook?.sections, !secs.isEmpty, secs.count <= 50 else { return [] }
        return secs
    }

    /// Description text to show in "About". Returns nil to skip the section when:
    ///  - no description
    ///  - stripped text is blank
    ///  - stripped text is < 80 chars (likely just a narrator credit line)
    var aboutText: String? {
        guard let raw = audiobook?.description else { return nil }
        let stripped = raw.strippingHTML
        guard stripped.count >= 80 else { return nil }
        return stripped
    }
}
