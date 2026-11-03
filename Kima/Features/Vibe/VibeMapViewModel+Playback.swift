import Foundation
import Observation

// MARK: - Map playback and cancellable queue work
//
// Split out of VibeMapViewModel. Methods only; `operationTasks` stays a stored property on the
// class (Swift allows no stored properties in extensions) and is now reachable from this file.

extension VibeMapViewModel {

    /// Fetches the full `Track` for `trackId` and plays it alone, like the other single-track play sites.
    func play(trackId: String, client: KimaAPIClient, player: PlaybackController) async {
        guard !isPlayLoading else { return }
        isPlayLoading = true
        playError = nil
        defer { isPlayLoading = false }
        do {
            let track = try await client.getTrack(id: trackId)
            player.play(tracks: [track], startAt: 0)
            operationSourceId = nil
        } catch {
            playError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Runs a map action that may ask "replace the queue?" or wait on the network, so closing the map can cancel it.
    func launch(_ work: @escaping @MainActor () async -> Void) {
        let id = UUID()
        operationTasks[id] = Task { @MainActor [weak self] in
            await work()
            self?.operationTasks[id] = nil
        }
    }

    /// Cancels every running map action (each one waiting on the replace question answers "no").
    func cancelOperations() {
        operationTasks.values.forEach { $0.cancel() }
        operationTasks = [:]
    }
}
