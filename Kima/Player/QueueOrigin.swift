import Foundation

/// What built the current queue, when it was something more than a plain list. The vibe map sets this
/// after it starts a queue; any new queue clears it.
enum QueueOrigin: Equatable, Sendable {
    case songPath
    case playSimilar
    case blend

    /// Plain name used in prompts, e.g. "song path".
    var name: String {
        switch self {
        case .songPath: return "song path"
        case .playSimilar: return "play similar"
        case .blend: return "blend"
        }
    }

    /// How a sentence names the playing queue of this kind, e.g. "the song path".
    var playingPhrase: String {
        switch self {
        case .songPath: return "the song path"
        case .playSimilar: return "the similar tracks"
        case .blend: return "the blend"
        }
    }

    /// How a sentence names a new queue of this kind, e.g. "a song path".
    var newQueuePhrase: String {
        switch self {
        case .songPath: return "a song path"
        case .playSimilar: return "similar tracks"
        case .blend: return "a blend"
        }
    }

    /// How a sentence names a new queue of the kind already playing, e.g. "a new song path".
    var anotherPhrase: String {
        switch self {
        case .songPath: return "a new song path"
        case .playSimilar: return "new similar tracks"
        case .blend: return "a new blend"
        }
    }

    /// The line the queue sheet shows, e.g. "song path — 12 tracks".
    func header(trackCount: Int) -> String {
        "\(name) — \(trackCount) track\(trackCount == 1 ? "" : "s")"
    }
}
