import SwiftUI

/// What the panels and the help list sit in: a title, with an optional small control at its end, over
/// the content, left of the rail. The rail's back button is the one way out. No box: like the readout,
/// a panel sits on the map's dark fade (`VibeFadeBackdrop`), and only its search field keeps a hairline.
struct VibePanelCard<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            HStack(spacing: KimaSpacing.md) {
                KimaKicker(title: title, dotColor: KimaColor.ambient)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                accessory()
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            content()
        }
        .padding(.leading, KimaSpacing.lg)
    }
}

extension VibePanelCard where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

/// A small muted line inside a panel ("searching…", "no matches", "pick a different track…").
struct VibePanelNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(KimaType.caption)
            .foregroundStyle(KimaColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A failure inside the readout or a panel, in the danger colour.
struct VibeErrorLine: View {
    let text: String
    let id: String

    init(_ text: String, id: String) {
        self.text = text
        self.id = id
    }

    var body: some View {
        Text(text)
            .font(KimaType.caption)
            .foregroundStyle(KimaColor.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(id)
    }
}

/// The full-width action at the bottom of a panel ("generate path", "blend", "play result"): a soft
/// fill with no edge. Dims itself when its button is disabled.
struct VibePanelButtonLabel: View {
    let title: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
        Text(title)
            .font(KimaType.body)
            .foregroundStyle(KimaColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: KimaLayout.minTouchTarget)
            .background(KimaColor.surfaceHover, in: shape)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .kimaDisabled()
    }
}
