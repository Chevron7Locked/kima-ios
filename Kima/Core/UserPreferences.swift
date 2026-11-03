import Foundation
import Observation

// MARK: - UserPreferences

/// Persisted per-user preferences backed by UserDefaults, read and written through `UserPreferences.shared`.
/// The speed keys are shared with PlaybackController's own UserDefaults reads, so a write here applies to the
/// next playback session; the Settings UI also updates the live `PlaybackController`.
@MainActor
@Observable
final class UserPreferences {
    static let shared = UserPreferences()

    // MARK: - Stored properties

    /// Default audiobook playback speed (0.75–2.0×).
    /// Key shared with PlaybackController ("kima.speed.audiobook"): PlaybackController reads
    /// this on init so a restart picks up the new default without extra wiring.
    /// The Settings UI also updates the live player instance in-session.
    var defaultAudiobookSpeed: Float {
        didSet { UserDefaults.standard.set(defaultAudiobookSpeed, forKey: Keys.audiobookSpeed) }
    }

    /// Default podcast playback speed (0.75–2.0×).
    /// Key shared with PlaybackController ("kima.speed.podcast") — same rationale as above.
    var defaultPodcastSpeed: Float {
        didSet { UserDefaults.standard.set(defaultPodcastSpeed, forKey: Keys.podcastSpeed) }
    }

    // MARK: - Init

    private init() {
        let abSpeed = UserDefaults.standard.float(forKey: Keys.audiobookSpeed)
        defaultAudiobookSpeed = abSpeed > 0 ? abSpeed : 1.0

        let podSpeed = UserDefaults.standard.float(forKey: Keys.podcastSpeed)
        defaultPodcastSpeed = podSpeed > 0 ? podSpeed : 1.0

    }

    // MARK: - Keys

    private enum Keys {
        static let audiobookSpeed       = "kima.speed.audiobook"       // shared with PlaybackController
        static let podcastSpeed         = "kima.speed.podcast"         // shared with PlaybackController
    }
}
