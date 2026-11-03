import Foundation

/// One curated "words of power" line + the mood vectors it fits (empty = general).
/// Decodes from the bundled `HypeLines.json` (`{"t": "<line>", "m": ["<moodKey>"...]}`).
struct HypeLine: Decodable {
    let text: String
    /// Mood keys this line fits (matching `VibeMoodPalette` keys). Empty = general.
    let moods: Set<String>

    enum CodingKeys: String, CodingKey { case text = "t", moods = "m" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        moods = Set(try c.decodeIfPresent([String].self, forKey: .moods) ?? [])
    }

    init(_ text: String, _ moods: Set<String> = []) {
        self.text = text
        self.moods = moods
    }
}

/// The hand-curated deck of feel-good lines behind the Home hero's daily line. Always about the listener (their
/// spark, taste, day), warm with a little swagger. It is the quality floor under the optional AI "warp".
/// Lines load once from the bundled `HypeLines.json`; if that is missing or unparseable, a small inline set
/// keeps the deck from being empty.
enum HypeDeck {

    static let lines: [HypeLine] = loadLines()

    private static func loadLines() -> [HypeLine] {
        guard let url = Bundle.main.url(forResource: "HypeLines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([HypeLine].self, from: data),
              !decoded.isEmpty
        else { return fallback }
        return decoded
    }

    /// Minimal safety net if the bundled deck can't be read — never let the hero go empty.
    private static let fallback: [HypeLine] = [
        HypeLine("your taste was never too much. it's the whole point."),
        HypeLine("the boldest thing today is to sound exactly like yourself."),
        HypeLine("make something today only you could've made."),
        HypeLine("you don't need anyone's permission to take up space."),
        HypeLine("the room gets a little warmer when you walk in."),
        HypeLine("you're doing better than the voice in your head admits."),
    ]

    // MARK: - Selection

    private static let recentKey = "kima.hype.recentLines"
    /// How many recent lines to remember and avoid, so the deck doesn't repeat itself day to day.
    private static let recentCap = 40

    /// Pick a mood-appropriate line for the current listening `moods` (VibeMoodPalette keys),
    /// avoiding lines shown recently. Falls back gracefully to general/any line when there's no
    /// mood signal or every candidate was recently shown.
    static func pick(for moods: [String]) -> String {
        let moodSet = Set(moods)
        let matches = lines.filter { $0.moods.isEmpty || !$0.moods.isDisjoint(with: moodSet) }
        let pool = matches.isEmpty ? lines : matches

        let recent = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        let fresh = pool.filter { !recent.contains($0.text) }
        let chosen = (fresh.isEmpty ? pool : fresh).randomElement() ?? lines.first ?? fallback[0]

        var updated = recent
        updated.append(chosen.text)
        if updated.count > recentCap { updated.removeFirst(updated.count - recentCap) }
        UserDefaults.standard.set(updated, forKey: recentKey)

        return chosen.text
    }

    // MARK: - Line of the day (stable across launches)
    //
    // One draw per day, cached; the final text is persisted.

    private static let lineKey = "kima.hype.lineOfDay"
    private static let dayKey = "kima.hype.lineOfDay.day"
    private static let warpedKey = "kima.hype.lineOfDay.warped"

    /// Today's dispatch line. First call today draws from the deck (mood-aware); every later
    /// call — relaunch, tab-switch, view re-mount — returns the SAME string, no new draw.
    static func lineOfDay(for moods: [String]) -> String {
        let d = UserDefaults.standard
        if d.string(forKey: dayKey) == dayStamp(), let cached = d.string(forKey: lineKey), !cached.isEmpty {
            return cached
        }
        let chosen = pick(for: moods)
        d.set(dayStamp(), forKey: dayKey)
        d.set(chosen, forKey: lineKey)
        d.set(false, forKey: warpedKey)
        return chosen
    }

    /// Today's cached line WITHOUT drawing a new one — the instant, no-flip display path.
    static func cachedLineIfToday() -> String? {
        guard UserDefaults.standard.string(forKey: dayKey) == dayStamp(),
              let cached = UserDefaults.standard.string(forKey: lineKey), !cached.isEmpty
        else { return nil }
        return cached
    }

    /// True once the warp step for today's line has RESOLVED (warped, cliched-rejected, model
    /// unavailable, or failed) — one warp attempt per day, never a retry storm per launch.
    static var todayLineResolved: Bool {
        UserDefaults.standard.string(forKey: dayKey) == dayStamp()
            && UserDefaults.standard.bool(forKey: warpedKey)
    }

    /// Persist the AI-warped result AS today's line (final text of the day).
    static func recordWarp(_ warped: String) {
        let d = UserDefaults.standard
        d.set(dayStamp(), forKey: dayKey)
        d.set(warped, forKey: lineKey)
        d.set(true, forKey: warpedKey)
    }

    /// Mark the warp step done after a non-adopted outcome (model absent / cliched / failed)
    /// so the line stays as drawn and today's opens stop re-attempting.
    static func recordWarpSkipped() {
        let d = UserDefaults.standard
        d.set(dayStamp(), forKey: dayKey)
        d.set(true, forKey: warpedKey)
    }

    static func dayStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
