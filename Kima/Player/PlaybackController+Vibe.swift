import Foundation

// MARK: - Vibe mode
// Toggle logic, server availability check, and match-score reactive property. The stored properties mutated here
// are declared internal in PlaybackController.swift.

extension PlaybackController {

    // MARK: - Availability (re-checked at most once a minute, like the web)

    /// Fetch GET /api/system/features and cache the `vibeEmbeddings` flag. A good answer is reused for
    /// 60 s; a failed fetch changes nothing and the next call tries again.
    /// Same gate as the web's `useFeatures` hook.
    func checkVibeAvailability(client: KimaAPIClient) async {
        if let at = vibeFeaturesCheckedAt, Date().timeIntervalSince(at) < 60 { return }
        do {
            let features = try await client.getSystemFeatures()
            vibeEmbeddingsAvailable = features.vibeEmbeddings
            vibeFeaturesCheckedAt = Date()
        } catch {
            // Keep the last known answer (nil = button stays hidden); the next call retries.
        }
    }

    // MARK: - Toggle

    /// Starts or stops play similar for the playing track. While any vibe queue plays this only ends it.
    /// Start queues the track plus its 50 nearest matches; if a vibe queue started while those loaded,
    /// it asks before replacing it. Stop keeps the queue playing. Failures set `vibeError`.
    func toggleVibeMode(client: KimaAPIClient) async {
        guard let track = currentTrack else { return }

        // Stop path (play similar, song path or blend): end the vibe queue, keep the music playing.
        if isVibeQueue {
            queueOrigin = nil
            vibeSimilarities = [:]
            vibeError = nil
            vibeNotice = "similar tracks off"
            return
        }

        guard !isVibeLoading else { return }
        isVibeLoading = true
        defer { isVibeLoading = false }
        vibeError = nil

        do {
            let (similar, similarities) = try await client.getVibeSimilarTracksWithSimilarity(trackId: track.id, limit: 50)
            guard currentTrack?.id == track.id else { return }  // user moved on
            guard !similar.isEmpty else {
                vibeError = "no similar tracks in your library"
                return
            }
            guard await confirmVibeReplace(with: .playSimilar) else { return }
            var scores = similarities
            scores[track.id] = 1.0  // the source track is a perfect match
            playVibeQueue([track] + similar, origin: .playSimilar, similarities: scores)
            vibeNotice = "playing \(similar.count) similar track\(similar.count == 1 ? "" : "s")"
        } catch {
            vibeError = VibeErrorCopy.similar(error)
        }
    }

    /// Plays a vibe queue in order and records what built it. `similarities` (track id → 0–1) feed the
    /// match badge, which only play similar shows.
    func playVibeQueue(_ tracks: [Track], origin: QueueOrigin, similarities: [String: Double] = [:]) {
        guard !tracks.isEmpty else { return }
        play(tracks: tracks, startAt: 0, shuffle: false)
        queueOrigin = origin
        vibeSimilarities = origin == .playSimilar ? similarities : [:]
    }

    // MARK: - Replace confirm

    /// Asks before a new vibe queue replaces the one playing. True when nothing is in the way or the
    /// user agrees. A second request while one is open answers the first with "no", and cancelling
    /// the asking task answers "no" too, so the prompt never outlives its caller.
    func confirmVibeReplace(with new: QueueOrigin) async -> Bool {
        guard let current = queueOrigin else { return true }
        resolveVibeReplace(false)
        guard !Task.isCancelled else { return false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                vibeReplaceContinuation = continuation
                vibeReplacePrompt = VibeReplacePrompt(current: current, new: new)
            }
        } onCancel: {
            Task { @MainActor in self.resolveVibeReplace(false) }
        }
    }

    /// Answers the open "replace?" question (the dialog's buttons call this).
    func resolveVibeReplace(_ confirmed: Bool) {
        let continuation = vibeReplaceContinuation
        vibeReplaceContinuation = nil
        vibeReplacePrompt = nil
        continuation?.resume(returning: confirmed)
    }

    /// A screen that can show the replace question came on screen; it becomes the one that shows it.
    func addVibeReplaceHost(_ id: UUID) {
        vibeReplaceHosts.removeAll { $0 == id }
        vibeReplaceHosts.append(id)
    }

    func removeVibeReplaceHost(_ id: UUID) {
        vibeReplaceHosts.removeAll { $0 == id }
    }

    // MARK: - Match score

    /// Similarity between the play similar source and the current track, 0–100, for the badge. Nil unless
    /// a play similar queue plays (song path and blend show no badge, as on the web); 0 when the current
    /// track has no score.
    var vibeMatchScore: Int? {
        guard queueOrigin == .playSimilar else { return nil }
        let similarity = vibeSimilarities[currentTrack?.id ?? ""] ?? 0
        return Int((similarity * 100).rounded())
    }
}
