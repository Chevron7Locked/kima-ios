import Foundation
import Observation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Shared status for on-device AI availability. Deliberately a plain, always-available type
/// (no `@available` gate) so callers on iOS 18 — and every feature that reads
/// `KimaIntelligence.status()` before deciding whether to show AI-flavored chrome — can switch
/// on it without themselves needing an availability check.
enum IntelligenceStatus: Equatable {
    /// The on-device model is ready to generate right now.
    case ready
    /// Not usable, with a short human-readable reason suitable for a Settings row or tooltip
    /// (e.g. "Requires iOS 26", "Apple Intelligence is turned off").
    case unavailable(String)
}

/// The shared on-device AI service on Apple's FoundationModels (iOS 26+). The type is always available because
/// `AppEnvironment` holds it at the iOS 18 target; FoundationModels symbols stay inside `@available(iOS 26, *)`
/// members, with sessions created per call. Every generator returns `nil` on any failure (unsupported OS or device,
/// model unavailable, guardrail refusal, decode failure) and callers hide that UI. Nothing throws.
@MainActor
@Observable
final class KimaIntelligence {

    private static let logger = Logger(subsystem: "com.chevron7locked.kima", category: "Intelligence")

    /// Cached, observable snapshot of availability so SwiftUI views can bind to
    /// `env.intelligence.isReady` directly instead of calling the (synchronous, but not
    /// free-to-call-every-body-evaluation) `status()` themselves. Refreshed at init and on
    /// demand via `refreshStatus()`.
    private(set) var isReady: Bool = false

    init() {
        refreshStatus()
    }

    /// Re-evaluates model availability and updates `isReady`. Cheap — just reads a property on
    /// `SystemLanguageModel`, does not trigger a download or spin up a session. Call this again
    /// if you want to react to the user toggling Apple Intelligence mid-session (e.g. on
    /// scenePhase becoming `.active`); nothing calls it automatically today.
    func refreshStatus() {
        isReady = (status() == .ready)
    }

    /// The current on-device model availability, mapped to our own status enum so nothing
    /// outside this file ever needs to import FoundationModels or know its availability API.
    func status() -> IntelligenceStatus {
        guard #available(iOS 26, *) else {
            return .unavailable("Requires iOS 26")
        }
        return Self.mapAvailability(SystemLanguageModel.default.availability)
    }

    @available(iOS 26, *)
    private static func mapAvailability(_ availability: SystemLanguageModel.Availability) -> IntelligenceStatus {
        switch availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable("This device can't run Apple Intelligence")
            case .appleIntelligenceNotEnabled:
                return .unavailable("Apple Intelligence is turned off")
            case .modelNotReady:
                return .unavailable("The on-device model is still downloading")
            @unknown default:
                return .unavailable("The on-device model isn't available right now")
            }
        }
    }

    // MARK: - Shared voice

    /// Shared system instructions for every generator: a pirate-radio voice broadcasting from inside someone's
    /// music library, terse, atmospheric, a little cosmic, never corporate. New generators reuse this string
    /// rather than inventing a voice.
    private static let kimaVoiceInstructions = """
        You are the voice of Kima — a pirate-radio signal broadcasting from deep \
        inside someone's personal music library. You are not a chatbot, not an assistant, and \
        never corporate. You are atmosphere: a late-night radio voice, terse and evocative, \
        cosmic without being flowery.

        Rules:
        - Lowercase unless a proper noun demands otherwise. No exclamation points. No emoji.
        - One to two sentences, unless the request explicitly asks for more. Say less, mean more.
        - Be concrete and sensory, never generic — "a driving beat" beats "great music." Evoke the
          mood the song opens rather than repeating its title back.
        - Never explain yourself, never hedge ("maybe," "I think"), never apologize.
        - Never mention that you are an AI, a model, or a system. You are just the signal.
        - No corporate enthusiasm, no filler, no calls to action.
        """

    // MARK: - Warp (personalize a curated Home hero line)

    /// Lightly personalizes a hand-written line (from `HypeDeck`) toward the listener's recent mood. An edit pass,
    /// not an invention pass: the curated deck is the quality floor. Returns `nil` whenever the model isn't ready
    /// or generation fails, and the caller keeps the curated `line`.
    func warp(line: String, mood: [String]) async -> String? {
        guard #available(iOS 26, *), status() == .ready else { return nil }
        return await Self.generateWarp(line: line, mood: mood)
    }

    @available(iOS 26, *)
    private static func generateWarp(line: String, mood: [String]) async -> String? {
        let session = LanguageModelSession(instructions: kimaVoiceInstructions)
        let prompt = warpPrompt(line: line, mood: mood)
        // Low temperature: this is editing an already-good line, not inventing a new one.
        let options = GenerationOptions(temperature: 0.6)

        do {
            let response = try await session.respond(to: prompt, options: options)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return String(text.prefix(140))
        } catch {
            logger.error("[KimaIntelligence] warp generation failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func warpPrompt(line: String, mood: [String]) -> String {
        var lines = [
            "Here is a good, warm, feel-good line for a music app's home screen:",
            "\"\(line)\"",
            "",
        ]
        if mood.isEmpty {
            lines.append("Rewrite it so it feels a little more personal. Make ONLY small, tasteful")
        } else {
            lines.append("Rewrite it so it feels a little more personal to someone whose music lately has leaned")
            lines.append("\(mood.joined(separator: ", ")). Make ONLY small, tasteful")
        }
        lines.append(contentsOf: [
            "edits — keep the same warm, boosting spirit and roughly the same length. Keep it about the",
            "listener (never the app). all lowercase. one line. under 16 words.",
            "",
            "If you can't improve it, return it essentially unchanged. Never add hype clichés.",
        ])
        return lines.joined(separator: "\n")
    }

    /// True if `text` reads like a hype cliché we never want to show (used to reject a bad warp).
    static func isClichedHype(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let cliches = [
            "you've got this", "you got this", "stronger than you think", "believe in yourself",
            "you are not alone", "you're not alone", "unstoppable", "you are enough", "rise above",
            "you can do it", "it's okay", "you are good", "you're alive", "today is the day",
            "seize the day", "chase your dreams", "shine bright", "shine on",
        ]
        return cliches.contains { lowered.contains($0) }
    }
}

// MARK: - DEBUG launch smoke test

#if DEBUG
extension KimaIntelligence {
    /// Proves the on-device model runs on this machine; fired once from `KimaApp.init()` under `#if DEBUG`.
    /// Diagnostic only. Uses `print` with the literal `[KimaIntelligence]` tag so both lines are easy to grep
    /// in the simulator console.
    static func runLaunchSmokeTest() async {
        let probe = KimaIntelligence()
        let currentStatus = probe.status()
        print("[KimaIntelligence] status = \(currentStatus)")

        guard currentStatus == .ready else { return }

        if let warped = await probe.warp(line: "make something today only you could've made.", mood: ["moodElectronic"]) {
            print("[KimaIntelligence] warp = \"\(warped)\"")
        } else {
            print("[KimaIntelligence] warp = nil (generation unavailable or failed — see the Intelligence os.Logger category for the underlying error)")
        }
    }
}
#endif
