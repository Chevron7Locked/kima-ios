import SwiftUI

/// The "•••" disc at the end of a detail screen's action row: holds that screen's rarer actions in a
/// menu so the row keeps one primary play and a few labeled controls. 36pt drawn, 44pt tappable.
/// `isWorking` swaps the dots for a spinner while one of its actions runs.
struct KimaMoreMenu<Content: View>: View {
    /// Spoken name of the menu, e.g. "album actions".
    var label: String = "more actions"
    var isWorking = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Group {
                if isWorking {
                    ProgressView().tint(KimaColor.textMuted).scaleEffect(0.7)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KimaColor.textSecondary)
                }
            }
            .frame(width: 36, height: 36)
            .background(KimaColor.surface, in: Circle())
            .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
            .kimaHitTarget()
        }
        .accessibilityLabel(label)
    }
}

/// A labeled secondary control for a detail screen's action row ("shuffle", "radio"): icon and short word on
/// a quiet capsule, so it never competes with the amber play beside it. At accessibility text sizes the word
/// drops to the spoken label and the control becomes an icon disc, so the row still fits one line.
struct KimaActionPill: View {
    let title: String
    let systemImage: String
    var isLoading = false
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            KimaIconDiscButton(systemName: systemImage, glyphSize: 15, label: title,
                               isLoading: isLoading, action: action)
        } else {
            KimaPrimaryButton(title: title, isLoading: isLoading, systemImage: systemImage,
                              style: .secondary, size: .compact, action: action)
                .buttonStyle(.plain)
                .disabled(isLoading)
        }
    }
}
