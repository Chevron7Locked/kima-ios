import Foundation

/// Measures listening as capped deltas between 1 Hz engine positions and reports it; the server decides what
/// counts as a play. The cap makes a scrub to the end worth almost nothing and makes a stalled feed undercount,
/// never overcount. A seek, track change or reload resets the count. Same counting rule as the web app; change
/// both together.
enum PlayRule {
    /// Most a single tick may add. The web feed fires ~4x a second and caps at 1.5s;
    /// iOS's engine tick is 1 Hz (PlaybackEngine 1s periodic observer), so the cap
    /// must sit above one real tick — 2.0s absorbs jitter and background throttling
    /// while still refusing to credit a scrub.
    static let maxCreditedDeltaSeconds = 2.0

    /// Mirrors the server's floor. Below this no request is worth making.
    static let minTrackDurationSeconds = 30.0

    /// Nobody has to finish a long track. Four minutes is always enough.
    static let maxRequiredSeconds = 240.0

    /// How much of this track has to be heard before it is worth reporting.
    /// `nil` = the track can never qualify (a different answer than "large" —
    /// listening harder must not satisfy it). Unknown duration gets the
    /// four-minute bound, not a pass. Mirrors server `requiredListenSeconds`.
    static func requiredSeconds(for durationSeconds: Double?) -> Double? {
        guard let d = durationSeconds, d.isFinite, d > 0 else { return maxRequiredSeconds }
        if d <= minTrackDurationSeconds { return nil }
        return min(d / 2, maxRequiredSeconds)
    }
}

/// The measurement, kept free of engine and network so it is fully testable
/// (DEBUG launch self-check prints `[ListenMeter] PASS/FAIL` per case).
final class ListenMeter {
    private var listened = 0.0
    private var lastPosition: Double?
    private var reported = false
    private var durationSeconds: Double?

    init(durationSeconds: Double?) {
        self.durationSeconds = durationSeconds
    }

    var secondsListened: Double { listened }

    /// A new track, or a reload. Nothing carries over.
    func reset(durationSeconds: Double? = nil) {
        listened = 0
        lastPosition = nil
        reported = false
        if let durationSeconds { self.durationSeconds = durationSeconds }
    }

    /// A duration that arrives mid-play belongs to the same listen: it keeps the
    /// count and the reported flag (resetting here is the double-count trap).
    func setDuration(_ durationSeconds: Double?) {
        self.durationSeconds = durationSeconds
    }

    /// A seek breaks the chain of deltas rather than producing one enormous one.
    func breakChain() {
        lastPosition = nil
    }

    /// Feed a position. Returns true exactly once — on the tick where the
    /// listening first earns a report.
    @discardableResult
    func observe(_ time: Double) -> Bool {
        guard time.isFinite else { return false }

        let previous = lastPosition
        lastPosition = time
        guard let previous else { return false }

        let delta = time - previous
        // Backwards is a seek. Forwards beyond one tick is a seek too: credit the
        // tick and no more, so dragging the scrubber buys a fraction of a second.
        guard delta > 0 else { return false }
        listened += min(delta, PlayRule.maxCreditedDeltaSeconds)

        guard !reported else { return false }
        guard let required = PlayRule.requiredSeconds(for: durationSeconds),
              listened >= required else { return false }

        reported = true
        return true
    }
}

#if DEBUG
extension ListenMeter {
    /// The five load-bearing meter-math cases the web app also tests, run once at launch in DEBUG.
    /// Prints one greppable line per case plus a summary; never gates app behavior.
    static func runLaunchSelfCheck() {
        var pass = 0, fail = 0
        func check(_ name: String, _ body: () -> Bool) {
            let ok = body()
            print("[ListenMeter] \(ok ? "PASS" : "FAIL") — \(name)")
            if ok { pass += 1 } else { fail += 1 }
        }

        func playForward(_ m: ListenMeter, from: Double, to: Double, step: Double = 1.0) -> Int {
            var reports = 0, t = from
            while t <= to + 1e-9 { if m.observe(t) { reports += 1 }; t += step }
            return reports
        }

        check("threshold crossed reports exactly once") {
            let m = ListenMeter(durationSeconds: 200)
            return playForward(m, from: 0, to: 190) == 1
        }
        check("scrub to the end credits almost nothing") {
            let m = ListenMeter(durationSeconds: 200)
            m.observe(0)
            let reported = m.observe(199)
            return !reported && m.secondsListened <= PlayRule.maxCreditedDeltaSeconds
        }
        check("backwards seek credits nothing") {
            let m = ListenMeter(durationSeconds: 200)
            _ = playForward(m, from: 100, to: 130)
            let before = m.secondsListened
            m.observe(10)
            return m.secondsListened == before
        }
        check("two sittings around a seek add up") {
            let m = ListenMeter(durationSeconds: 200)
            _ = playForward(m, from: 0, to: 60)
            m.breakChain()
            return playForward(m, from: 120, to: 166) == 1  // 60 + 46 real audio ≥ 100
        }
        check("track under the floor never counts") {
            let m = ListenMeter(durationSeconds: 25)
            return playForward(m, from: 0, to: 25) == 0 && playForward(m, from: 0, to: 25) == 0
        }
        check("unknown duration demands four minutes") {
            let m = ListenMeter(durationSeconds: 0)
            return playForward(m, from: 0, to: 200) == 0 && playForward(m, from: 200, to: 245) == 1
        }
        check("late duration keeps the reported flag") {
            let m = ListenMeter(durationSeconds: nil)
            _ = playForward(m, from: 0, to: 241)          // unknown → 240 required → reported
            m.setDuration(200)                              // duration arrives late
            return playForward(m, from: 241, to: 300) == 0 // must NOT report twice
        }

        print("[ListenMeter] self-check: \(pass) passed, \(fail) failed")
    }
}
#endif
