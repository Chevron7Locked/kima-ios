import SwiftUI

/// The help list over the bottom of the map: one line per gesture, per action under a selected star,
/// per tool, and for the icons without a word under them. It covers the readout or a panel while open
/// and changes neither; the rail's back button closes it. Scrolls when it is taller than the room.
struct VibeHelpView: View {

    /// One line: what to do (or an icon) and what it does.
    struct Line: Identifiable {
        let key: String
        /// SF Symbol shown instead of `key`.
        var symbol: String? = nil
        let meaning: String
        var id: String { key }
    }

    static let gestures = [
        Line(key: "tap a star", meaning: "details"),
        Line(key: "double-tap", meaning: "play"),
        Line(key: "drag", meaning: "turn"),
        Line(key: "pinch", meaning: "zoom"),
        Line(key: "two fingers", meaning: "move"),
    ]
    static let actions = [
        Line(key: "play", meaning: "plays this song"),
        Line(key: "play similar", meaning: "plays songs like it"),
        Line(key: "show similar", meaning: "lights up songs like it"),
        Line(key: "more like", meaning: "adds it to a blend"),
        Line(key: "less like", meaning: "a blend steers away from it"),
    ]
    static let tools = [
        Line(key: "song path", meaning: "plays a route between two songs"),
        Line(key: "blend", meaning: "mixes songs you pick"),
    ]
    static let icons = [
        Line(key: "back button", symbol: "arrow.uturn.backward", meaning: "closes or undoes the last thing"),
        Line(key: "labels button", symbol: "tag", meaning: "mood names on or off"),
        Line(key: "whole library button", symbol: "arrow.up.left.and.down.right.magnifyingglass",
             meaning: "show the whole library"),
    ]

    var body: some View {
        VibePanelCard(title: "help") {
            VibeSizedScroll {
                Grid(alignment: .leading, horizontalSpacing: KimaSpacing.md, verticalSpacing: KimaSpacing.xs) {
                    group(Self.gestures)
                    gap
                    group(Self.actions)
                    gap
                    group(Self.tools)
                    gap
                    group(Self.icons)
                }
                .font(KimaType.caption)
                .padding(.bottom, KimaSpacing.xs)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("vibe-tray-help")
        }
    }

    private var gap: some View {
        GridRow { Color.clear.frame(height: KimaSpacing.xs).gridCellColumns(2) }
    }

    @ViewBuilder
    private func group(_ lines: [Line]) -> some View {
        ForEach(lines) { line in
            GridRow(alignment: .firstTextBaseline) {
                Group {
                    if let symbol = line.symbol {
                        Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                    } else {
                        Text(line.key)
                    }
                }
                .foregroundStyle(KimaColor.textPrimary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(line.key): \(line.meaning)")
                Text(line.meaning)
                    .foregroundStyle(KimaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }
}
