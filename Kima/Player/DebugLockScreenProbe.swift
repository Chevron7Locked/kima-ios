#if DEBUG
import SwiftUI
import MediaPlayer

// MARK: - DebugLockScreenProbe

/// UI-test probe for the *published* lock-screen state (ticket 03, `-kima-fake-podcast` only):
/// reads `MPNowPlayingInfoCenter` back and renders what the system actually holds — the oracle is
/// the published value itself, never a re-derivation from engine state. The XCUITest runner lives
/// in another process; this is its window onto the one it can't reach. TimelineView keeps the
/// reading current between snapshots, matching `debugVibeReplaceMarker`'s marker pattern.
struct DebugLockScreenProbe: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Text(Self.publishedName)
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
                .accessibilityIdentifier("lock-screen-published")
        }
    }

    private static var publishedName: String {
        switch MPNowPlayingInfoCenter.default().playbackState {
        case .playing: return "playing"
        case .paused:  return "paused"
        case .stopped: return "stopped"
        default:       return "unknown"
        }
    }
}

extension View {
    /// Mounts the probe over the shell while a podcast seed is active; invisible to every other run.
    func debugLockScreenProbe(active: Bool) -> some View {
        overlay(alignment: .topLeading) {
            if active {
                DebugLockScreenProbe()
                    .padding(.leading, KimaSpacing.xs)
            }
        }
    }
}
#endif
