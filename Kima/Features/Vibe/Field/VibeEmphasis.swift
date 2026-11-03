import Foundation

/// How bright each star is meant to be right now, and the easing that gets it there.
struct VibeEmphasis {
    static let settleThreshold: Float = 0.003
    static let easeRate: Float = 7

    private(set) var values: [Float]

    init(count: Int) { values = [Float](repeating: 1, count: count) }

    /// The level each star should reach (the web map's values). Highlights lift their members to
    /// 1.35 and dim the rest to 0.12; a selection alone dims the rest to 0.6. The playing star is at
    /// least 1.5; the selected star is 1.7, over everything else.
    static func goals(count: Int, indexById: [String: Int], highlighted: Set<String>,
                      selected: String?, playing: String?) -> [Float] {
        let hasHighlights = !highlighted.isEmpty
        var goal = [Float](repeating: hasHighlights ? 0.12 : (selected != nil ? 0.6 : 1), count: count)
        if hasHighlights {
            for id in highlighted { if let i = indexById[id] { goal[i] = 1.35 } }
        }
        if let id = playing, let i = indexById[id] { goal[i] = max(goal[i], 1.5) }
        if let id = selected, let i = indexById[id] { goal[i] = 1.7 }
        return goal
    }

    /// Move every star toward its goal. Returns true once all have arrived, so uploads can stop.
    mutating func ease(toward goal: [Float], dt: Float, reduceMotion: Bool) -> Bool {
        let k = reduceMotion ? 1 : min(1, dt * Self.easeRate)
        var settled = true
        for i in 0..<min(values.count, goal.count) {
            let d = goal[i] - values[i]
            if abs(d) > Self.settleThreshold { values[i] += d * k; settled = false } else { values[i] = goal[i] }
        }
        return settled
    }
}
