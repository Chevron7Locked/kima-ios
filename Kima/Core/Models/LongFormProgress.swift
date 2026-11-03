import Foundation

// MARK: - LongFormProgress

/// Progress for an audiobook or a podcast episode (the server sends the same shape for both).
///
/// `lastPlayedAt` is decoded from the Prisma ISO 8601 string via a custom `init(from:)`.
/// The default JSONDecoder strategy expects epoch numbers; custom decode handles strings.
struct LongFormProgress: Codable, Sendable {
    let currentTime: Double
    let progress: Double   // 0-100 percent
    let isFinished: Bool
    let lastPlayedAt: Date

    private enum CodingKeys: String, CodingKey {
        case currentTime, progress, isFinished, lastPlayedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentTime    = try c.decode(Double.self, forKey: .currentTime)
        progress       = try c.decode(Double.self, forKey: .progress)
        isFinished     = try c.decode(Bool.self,   forKey: .isFinished)
        let raw        = try c.decode(String.self,  forKey: .lastPlayedAt)
        lastPlayedAt   = Formatters.parseISO8601OrDistantPast(raw)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(currentTime,  forKey: .currentTime)
        try c.encode(progress,     forKey: .progress)
        try c.encode(isFinished,   forKey: .isFinished)
        try c.encode(Formatters.iso8601Fractional.string(from: lastPlayedAt), forKey: .lastPlayedAt)
    }

    /// Optimistic local update: stamps `lastPlayedAt` with now.
    init(currentTime: Double, progress: Double, isFinished: Bool) {
        self.currentTime = currentTime
        self.progress = progress
        self.isFinished = isFinished
        self.lastPlayedAt = .now
    }
}
