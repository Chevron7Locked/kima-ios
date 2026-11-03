import Foundation

// MARK: - First-run & auth

extension KimaAPIClient {

    /// GET /api/onboarding/status — no auth. Drives create-account vs connect.
    func onboardingStatus() async throws -> OnboardingStatus {
        try await get("/onboarding/status", authed: false)
    }

    /// POST /api/auth/login. The server signals 2FA with HTTP 200 + `requires2FA: true` (not a 401);
    /// we surface that as `APIError.requires2FA` so the caller can prompt for a code and re-call with `token`.
    func login(username: String, password: String, token: String? = nil) async throws -> LoginResponse {
        var body = ["username": username, "password": password]
        if let token { body["token"] = token }
        let response: LoginResponse = try await post("/auth/login", body: body, authed: false)
        if response.requires2FA == true, token == nil {
            throw APIError.requires2FA
        }
        return response
    }

    /// GET /api/auth/me — validate the stored credential on launch.
    func me() async throws -> KimaUser {
        try await get("/auth/me", authed: true)
    }

    /// Lightweight library count (fetch 1 row, read `total`) — used by the connected-proof screen.
    func libraryCount(of kind: LibraryKind) async throws -> Int {
        let result: LibraryCount = try await get("/library/\(kind.rawValue)", query: ["limit": "1"], authed: true)
        return result.total
    }

    /// POST /api/device-link/verify — exchange a 6-char pairing code for a permanent API key. No auth.
    func deviceLinkVerify(code: String, deviceName: String) async throws -> DeviceLinkVerifyResponse {
        try await post("/device-link/verify", body: ["code": code, "deviceName": deviceName], authed: false)
    }

    /// POST /api/auth/logout — best-effort, fire-and-forget. Never throws; the caller is
    /// responsible for clearing local credentials regardless of whether the server acknowledges
    /// the request.
    func logout() async {
        await postNoContent("/auth/logout", authed: true)
    }

    /// DELETE /api/auth/account — permanently delete the authenticated user account.
    /// Throws on non-2xx (including 401 with refresh retry via deleteChecked).
    /// On success the caller is responsible for clearing local credentials (sign-out flow).
    /// Note: the backend endpoint is being built in parallel; once live, this wires straight through.
    func deleteAccount() async throws {
        try await deleteChecked("/auth/account", authed: true)
    }

    /// POST /api/onboarding/register — create the first (admin) account on a fresh server.
    /// Unauthenticated; returns a JWT token + the new user on success.
    func onboardingRegister(username: String, password: String) async throws -> OnboardingRegisterResponse {
        try await post("/onboarding/register", body: ["username": username, "password": password], authed: false)
    }

    /// POST /api/onboarding/complete — mark onboarding finished. Best-effort; never throws.
    /// Called after a successful register; the caller proceeds to the library scan regardless.
    func onboardingComplete() async {
        await postNoContent("/onboarding/complete", authed: true)
    }

    /// POST /api/library/scan — kick off a full library import. Returns the job ID for polling.
    func libraryScan() async throws -> LibraryScanResponse {
        try await post("/library/scan", body: [:], authed: true)
    }

    /// GET /api/library/scan/status/:jobId — poll scan progress until status is
    /// `"completed"` or `"failed"`. Callers should poll on a 2-second interval.
    func libraryScanStatus(jobId: String) async throws -> LibraryScanStatus {
        try await get("/library/scan/status/\(jobId)", authed: true)
    }
}
