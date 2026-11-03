import Foundation

// MARK: - What's-new domain (release window)
// The server decides what is pending (server-side acknowledgements, so a second device asks too); a client can
// never claim a release was seen. The once-per-session fetch caching lives in WhatsNewGateModel, not here.

private struct WhatsNewEmptyBody: Encodable {}

/// Accepts any JSON object — used where the response's fields are read for
/// nothing (state is re-fetched from the source), and a Bool field would make
/// a typed dictionary decode throw.
private struct WhatsNewAnyResponse: Decodable {
    init(from decoder: Decoder) throws {}
}
private struct WhatsNewChoiceBody: Encodable {
    let key: String
    let enabled: Bool
}
private struct WhatsNewDecisionBody: Encodable {
    let decision: String   // "rebuild" | "keep" | "remove"
}
private struct WhatsNewSaveBody: Encodable {
    let mixId: String
}

/// GET /whats-new/pending envelope: `{ releases: Release[] }`.
private struct WhatsNewPendingResponse: Decodable {
    let releases: [WhatsNewRelease]
}

extension KimaAPIClient {

    /// What this user still needs shown, oldest first (server-sorted).
    func getWhatsNewPending() async throws -> [WhatsNewRelease] {
        let res: WhatsNewPendingResponse = try await get("/whats-new/pending", authed: true)
        return res.releases
    }

    /// Every release newest first, each item with its recorded answer, done or open state. Reading writes nothing.
    func getChangelog() async throws -> WhatsNewChangelog {
        try await get("/whats-new/changelog", authed: true)
    }

    /// Whether a newer server release exists (checked by the server once a day).
    func getServerUpdateStatus() async throws -> ServerUpdateStatus {
        try await get("/whats-new/update-status", authed: true)
    }

    /// How many released actions this user was asked to take that the server cannot yet see done.
    func getOpenRequirementCount() async throws -> Int {
        struct OpenResponse: Decodable { let count: Int }
        let res: OpenResponse = try await get("/whats-new/open", authed: true)
        return res.count
    }

    /// Record an explicit answer to one `choice` item. Throws on failure, so the
    /// caller can put the button back.
    func postWhatsNewChoice(version: String, key: String, enabled: Bool) async throws {
        let body = WhatsNewChoiceBody(key: key, enabled: enabled)
        let _: WhatsNewAnyResponse = try await postJSON("/whats-new/\(version)/choice", body: body, authed: true)
    }

    /// Close a release. Unanswered choices are settled server-side at their
    /// defaults (silence is never consent — the response names them). Throws:
    /// the window must STAY OPEN on failure, saying so.
    func postWhatsNewDismiss(version: String) async throws {
        let _: WhatsNewAnyResponse = try await postJSON("/whats-new/\(version)/dismiss",
                                                        body: WhatsNewEmptyBody(), authed: true)
    }

    /// The user's saved mood mix + their recorded answer (nil mix = none).
    func getMoodMixState() async throws -> MoodMixReleaseState {
        try await get("/whats-new/mood-mixes", authed: true)
    }

    /// Rebuild / keep / remove. "keep" on a retired mix is refused (400) —
    /// APIError.http surfaces the server's copy for that case.
    func decideMoodMixes(_ decision: String) async throws {
        let body = WhatsNewDecisionBody(decision: decision)
        let _: MoodMixReleaseState = try await postJSON("/whats-new/mood-mixes/decision",
                                                        body: body, authed: true)
    }

    /// Copy the saved mix into an ordinary playlist (idempotent server-side).
    func saveMoodMixAsPlaylist(mixId: String) async throws -> MoodMixSaveResult {
        try await postJSON("/whats-new/mood-mixes/save", body: WhatsNewSaveBody(mixId: mixId), authed: true)
    }

    /// Re-embed every track with the current analyzer (POST /analysis/vibe/start
    /// {force:true}), the window's run-from-window action.
    func resetVibeEmbeddings() async throws {
        struct ForceBody: Encodable { let force: Bool }
        let _: [String: String] = try await postJSON("/analysis/vibe/start",
                                                     body: ForceBody(force: true), authed: true)
    }
}
