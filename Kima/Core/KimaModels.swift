import Foundation

// Codable models for the first-run / session surface: onboarding, auth/login, device-link, and the library-scan
// lifecycle. Kept at Core root, not Core/Models/, because they are the bootstrap contract the app needs before
// any feature loads.

/// GET /api/onboarding/status — decides "create the first account" vs "connect to an existing one".
struct OnboardingStatus: Codable, Equatable {
    let hasAccount: Bool
    let needsOnboarding: Bool
    let registrationOpen: Bool
}

/// The authenticated user.
struct KimaUser: Codable, Equatable, Identifiable {
    let id: String
    let username: String
    let role: String?
    let onboardingComplete: Bool?
}

/// POST /api/auth/login response. `requires2FA == true` (with HTTP 200) means re-submit with a code.
struct LoginResponse: Codable {
    let token: String?
    let refreshToken: String?
    let user: KimaUser?
    let requires2FA: Bool?
}

/// POST /api/device-link/verify — exchange a pairing code for a permanent API key.
struct DeviceLinkVerifyResponse: Codable {
    let success: Bool
    let apiKey: String?
    let userId: String?
    let username: String?
}

/// POST /api/onboarding/register response — returns a JWT token + the new user on success.
struct OnboardingRegisterResponse: Codable {
    let token: String?
    let user: KimaUser?
}

/// POST /api/library/scan response — the async job that drives the initial library import.
struct LibraryScanResponse: Codable {
    let message: String?
    let jobId: String
    let musicPath: String?
}

/// GET /api/library/scan/status/:jobId response.
/// `status` is one of `"active"`, `"waiting"`, `"completed"`, `"failed"`.
struct LibraryScanStatus: Codable {
    let status: String
    /// Server-reported progress 0–100 (may be nil while status is "waiting").
    let progress: Double?

    struct ScanResult: Codable {
        let tracksAdded: Int?
        let tracksUpdated: Int?
        let tracksRemoved: Int?
    }

    let result: ScanResult?
}

/// `GET /api/library/{albums|artists|tracks}` returns `{ <kind>: [...], total, offset, limit }`.
/// We decode only `total` for the connected-proof counts (works for all three responses).
struct LibraryCount: Codable { let total: Int }

enum LibraryKind: String { case albums, artists, tracks }

/// Which credential type to send on authenticated requests.
/// `.jwt` → `Authorization: Bearer <token>`; `.apiKey` → `x-api-key: <key>`.
enum KimaCredential: Sendable {
    case jwt(String)
    case apiKey(String)

    /// Load the credential saved for `server` from Keychain; one saved for any other server is
    /// never returned. API key takes precedence over JWT (device-link pairing wins).
    static func fromKeychain(for server: KimaServer) -> KimaCredential? {
        if let key = KeychainStore.credential(KeychainStore.apiKey, for: server) { return .apiKey(key) }
        if let token = KeychainStore.credential(KeychainStore.accessToken, for: server) { return .jwt(token) }
        return nil
    }
}
