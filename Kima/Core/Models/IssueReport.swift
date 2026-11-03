import Foundation

/// A single in-app issue report, saved to `issue-reports.json` on the phone. Context (what's playing, where, when,
/// which build, phone and server) is captured at tap time; every captured field is optional and best-effort.
/// `GitHubIssueLink` sends only the note, versions, device model and screen.
struct IssueReport: Codable, Identifiable, Hashable {
    let id: UUID
    /// When the report was filed (device local clock).
    let capturedAt: Date
    /// Free-text "what happened?" from the user. May be empty.
    var note: String

    // MARK: Auto-captured context (best-effort snapshot at tap time)

    /// Best-effort screen / tab hint, e.g. "Home", "Library", "Audiobooks".
    var screen: String?
    /// Coarse playback kind: "music", "audiobook", "podcast", or "nothing playing".
    var playbackType: String?
    /// Now-playing title (track title or long-form title).
    var nowPlayingTitle: String?
    /// Now-playing artist / author / show.
    var nowPlayingArtist: String?
    /// Playhead position in seconds at capture time.
    var positionSeconds: Double?
    /// Item duration in seconds at capture time.
    var durationSeconds: Double?
    /// Whether audio was actively playing.
    var isPlaying: Bool?

    /// App marketing version (`CFBundleShortVersionString`).
    var appVersion: String?
    /// App build (`CFBundleVersion`).
    var appBuild: String?
    /// Server host the app was connected to (no scheme, no path).
    var serverHost: String?
    /// OS name and version, e.g. "iOS 26.0".
    var systemVersion: String?
    /// Hardware model identifier, e.g. "iPhone17,1".
    var deviceModel: String?

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        note: String = "",
        screen: String? = nil,
        playbackType: String? = nil,
        nowPlayingTitle: String? = nil,
        nowPlayingArtist: String? = nil,
        positionSeconds: Double? = nil,
        durationSeconds: Double? = nil,
        isPlaying: Bool? = nil,
        appVersion: String? = nil,
        appBuild: String? = nil,
        serverHost: String? = nil,
        systemVersion: String? = nil,
        deviceModel: String? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.note = note
        self.screen = screen
        self.playbackType = playbackType
        self.nowPlayingTitle = nowPlayingTitle
        self.nowPlayingArtist = nowPlayingArtist
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.isPlaying = isPlaying
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.serverHost = serverHost
        self.systemVersion = systemVersion
        self.deviceModel = deviceModel
    }
}

// MARK: - Display helpers

extension IssueReport {
    /// Abbreviated date + short time, e.g. "Jul 9, 2026 at 3:41 PM".
    var capturedTimeString: String {
        capturedAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// "1:23 / 3:45" (position / duration), or just the position, or nil when neither is known.
    var positionString: String? {
        let pos = Self.clock(positionSeconds)
        let dur = Self.clock(durationSeconds)
        switch (pos, dur) {
        case let (p?, d?): return "\(p) / \(d)"
        case let (p?, nil): return p
        default: return nil
        }
    }

    /// "Song Title — Artist" (either part may be absent), or nil when nothing was playing.
    var nowPlayingSummary: String? {
        switch (nowPlayingTitle, nowPlayingArtist) {
        case let (t?, a?): return "\(t) — \(a)"
        case let (t?, nil): return t
        case let (nil, a?): return a
        default: return nil
        }
    }

    /// One-line context digest for the viewer list, e.g.
    /// "Home · music · Song — Artist · 1:23 / 3:45".
    var contextLine: String {
        var parts: [String] = []
        if let screen { parts.append(screen) }
        if let playbackType { parts.append(playbackType) }
        if let nowPlayingSummary { parts.append(nowPlayingSummary) }
        if let positionString { parts.append(positionString) }
        return parts.isEmpty ? "no context captured" : parts.joined(separator: " · ")
    }

    /// Formats a seconds value as `m:ss` (`h:mm:ss` from an hour), tolerating nil / non-finite / negative input.
    static func clock(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        return seconds.durationFormatted
    }
}
