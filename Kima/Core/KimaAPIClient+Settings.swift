import Foundation

// MARK: - Settings domain
// updateSettings/updateSystemSettings are POSTs with partial bodies; values go up as typed and the server's zod
// schema is the authority on range and format. listenbrainzToken is write-only (never echoed back).

/// GET /system-settings/public-config — any signed-in user.
struct PublicConfig: Decodable, Sendable {
    let publicUrl: String?
    /// Whether this user may start downloads (operator-only unless an admin allows members). A server older than
    /// that rule does not send it and does not restrict downloads, so a missing value is true.
    let canAcquire: Bool

    private enum CodingKeys: String, CodingKey { case publicUrl, canAcquire }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        publicUrl = try c.decodeIfPresent(String.self, forKey: .publicUrl)
        canAcquire = try c.decodeIfPresent(Bool.self, forKey: .canAcquire) ?? true
    }
}

extension KimaAPIClient {

    func getPublicConfig() async throws -> PublicConfig {
        try await get("/system-settings/public-config", authed: true)
    }

    /// GET /settings — the user's settings with secrets stripped.
    func getUserSettings() async throws -> UserSettings {
        try await get("/settings", authed: true)
    }

    /// POST /settings — partial update (token save/clear, live-sharing switch).
    func updateUserSettings(_ patch: UserSettingsPatch) async throws -> UserSettings {
        try await postJSON("/settings", body: patch, authed: true)
    }

    /// GET /system-settings — consumed slice (maxQueueLength) only.
    func getSystemQueueLimit() async throws -> SystemSettingsSlice {
        try await get("/system-settings", authed: true)
    }

    /// POST /system-settings — partial update (queue limit). Admin-only server-side, so the row is hidden (not
    /// disabled) unless role == "admin". The POST answers {success, requiresRestart}, not the row, so the stored value
    /// is read back with a GET; decoding fields from the ack would turn absent keys into defaults and the UI would lie.
    @discardableResult
    func updateSystemQueueLimit(_ maxQueueLength: Int) async throws -> SystemSettingsSlice {
        struct Ack: Decodable { let success: Bool? }
        // 2xx only: zod rejections answer 400, which the transport raises as
        // APIError.http before this line can decode anything.
        let _: Ack = try await postJSON("/system-settings", body: SystemSettingsPatch(maxQueueLength: maxQueueLength), authed: true)
        return try await getSystemQueueLimit()
    }
}
