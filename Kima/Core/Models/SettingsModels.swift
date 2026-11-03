import Foundation

// MARK: - Settings domain (user + system)
//
// `listenbrainzToken` is WRITE-ONLY: accepted on POST (null clears), never echoed on GET, which answers with
// `hasListenbrainzToken` instead. The client must never store the token locally; the server encrypts it at rest.

/// GET /settings — the user's row with secrets stripped (publicSettings()).
struct UserSettings: Codable, Sendable {
    var playbackQuality: String = "original"
    var wifiOnly: Bool = false
    var offlineEnabled: Bool = false
    var maxCacheSizeMb: Int = 0
    /// Saved-state flag only — the token value itself never crosses the wire.
    var hasListenbrainzToken: Bool = false
    var shareLiveListening: Bool = true
    /// True when this user's listening is the one KIMA_PUBLIC_VIBE shares;
    /// the "share what I'm playing" switch only exists when this is true.
    var liveSharingAvailable: Bool = false
    /// Unknown keys are ignored; every field has a safe fallback so one
    /// server-side rename can't blank the settings screen.
    private enum CodingKeys: String, CodingKey {
        case playbackQuality, wifiOnly, offlineEnabled, maxCacheSizeMb
        case hasListenbrainzToken, shareLiveListening, liveSharingAvailable
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playbackQuality = try c.decodeIfPresent(String.self, forKey: .playbackQuality) ?? "original"
        wifiOnly = try c.decodeIfPresent(Bool.self, forKey: .wifiOnly) ?? false
        offlineEnabled = try c.decodeIfPresent(Bool.self, forKey: .offlineEnabled) ?? false
        maxCacheSizeMb = try c.decodeIfPresent(Int.self, forKey: .maxCacheSizeMb) ?? 0
        hasListenbrainzToken = try c.decodeIfPresent(Bool.self, forKey: .hasListenbrainzToken) ?? false
        shareLiveListening = try c.decodeIfPresent(Bool.self, forKey: .shareLiveListening) ?? true
        liveSharingAvailable = try c.decodeIfPresent(Bool.self, forKey: .liveSharingAvailable) ?? false
    }
    init() {}
}

/// The queue-limit slice of GET /system-settings (the full row is web-only;
/// iOS consumes exactly this one number — the server echo carries it back).
struct SystemSettingsSlice: Codable, Sendable {
    var maxQueueLength: Int = 10000
    private enum CodingKeys: String, CodingKey { case maxQueueLength }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxQueueLength = try c.decodeIfPresent(Int.self, forKey: .maxQueueLength) ?? 10000
    }
    init() {}
}

/// POST bodies — field sets mirror settingsSchema/systemSettingsSchema; the
/// token body carries an explicit null to clear (key presence is the signal).
struct UserSettingsPatch: Encodable {
    var listenbrainzToken: String??     // nil=omit, .some(nil)=clear, string=save
    var shareLiveListening: Bool?
    enum CodingKeys: String, CodingKey { case listenbrainzToken, shareLiveListening }
    init(listenbrainzToken: String?? = nil, shareLiveListening: Bool? = nil) {
        self.listenbrainzToken = listenbrainzToken
        self.shareLiveListening = shareLiveListening
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Double-optional semantics: .some(nil) must encode an EXPLICIT JSON
        // null (that is how the server distinguishes "clear" from "omit") —
        // encodeIfPresent skips nil keys, so encode the String? directly.
        if case .some(let token) = listenbrainzToken {
            try c.encode(token, forKey: .listenbrainzToken)
        }
        try c.encodeIfPresent(shareLiveListening, forKey: .shareLiveListening)
    }
}

struct SystemSettingsPatch: Encodable {
    var maxQueueLength: Int?
}
