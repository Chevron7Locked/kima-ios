import SwiftUI

// MARK: - Shared disabled-state dimming

/// Dims the content when the surrounding control is disabled (reads `@Environment(\.isEnabled)`).
private struct KimaDisabledModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    let disabledOpacity: Double

    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 1.0 : disabledOpacity)
    }
}

extension View {
    /// Dims this view to `opacity` when `@Environment(\.isEnabled)` is `false`.
    func kimaDisabled(opacity: Double = 0.4) -> some View {
        modifier(KimaDisabledModifier(disabledOpacity: opacity))
    }
}

// MARK: - KimaIconDiscButton

/// Round 36pt secondary control: a muted glyph on a surface disc with a hairline ring, tappable across 44pt.
/// `isLoading` swaps the glyph for a spinner and disables it.
struct KimaIconDiscButton: View {
    let systemName: String
    let glyphSize: CGFloat
    let label: String
    var isLoading = false
    /// A toggle that is on: amber glyph and ring (amber is the only "on" ring).
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().controlSize(.small).tint(KimaColor.brand)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: glyphSize, weight: .medium))
                        .foregroundStyle(isOn ? KimaColor.brand : KimaColor.textSecondary)
                }
            }
            .frame(width: 36, height: 36)
            .background(KimaColor.surface, in: Circle())
            .overlay(Circle().strokeBorder(isOn ? KimaColor.brand.opacity(0.6) : KimaColor.hairline, lineWidth: 1))
            .kimaHitTarget(growsLayout: false)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - KimaPrimaryButton

/// Call-to-action. `.primary` is the amber fill (one per view), `.secondary` the neutral one beside
/// it, `.destructive` a deep red for delete. `.full` spans the width with the icon after the label;
/// `.compact` hugs its label at touch height with the icon first, for a button in a row.
/// Disabled fades the whole button.
struct KimaPrimaryButton: View {
    enum Style { case primary, secondary, destructive }
    enum Size { case full, compact }

    let title: String
    var isLoading: Bool = false
    var systemImage: String? = nil
    var style: Style = .primary
    var size: Size = .full
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: size == .full ? KimaSpacing.sm : KimaSpacing.xs) {
                if isLoading { ProgressView().tint(foreground) }
                if size == .compact, let systemImage, !isLoading { Image(systemName: systemImage) }
                Text(title)
                    .lineLimit(1)               // never wrap the CTA label ("save / changes")
                    .fixedSize(horizontal: true, vertical: false)
                if size == .full, let systemImage, !isLoading { Image(systemName: systemImage) }
            }
            .font(size == .full ? KimaType.headline : KimaType.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: size == .full ? .infinity : nil)
            .padding(.horizontal, size == .full ? 0 : KimaSpacing.lg)
            .padding(.vertical, size == .full ? KimaSpacing.lg : 0)
            .frame(minHeight: size == .full ? nil : KimaLayout.minTouchTarget)
            .background(Capsule().fill(fill))
            .overlay {
                if style == .secondary { Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1) }
            }
            .contentShape(Capsule())
            .kimaDisabled(opacity: 0.5)
        }
    }

    private var foreground: Color { style == .primary ? KimaColor.onBrand : KimaColor.textPrimary }

    private var fill: Color {
        switch style {
        case .primary:     KimaColor.brand
        case .secondary:   KimaColor.fillQuiet
        case .destructive: KimaColor.dangerFill
        }
    }
}

// MARK: - Card press physics

/// Shared press feel for card-style buttons (covers, tiles, rail cards): a tight, fully-damped
/// spring scale-down while held — picking up a physical object, not a bouncy toy. No overshoot
/// (`dampingFraction` ≥ 0.8): motion should read as precise, never elastic.
struct KimaCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
            // A soft tap the moment the card is pressed — every cover/tile across the app.
            .sensoryFeedback(trigger: configuration.isPressed) { _, pressed in
                pressed ? .impact(weight: .light, intensity: 0.6) : nil
            }
    }
}

extension ButtonStyle where Self == KimaCardPressStyle {
    /// The shared card-press spring — use in place of `.plain` on cover/tile card buttons.
    static var kimaCard: KimaCardPressStyle { KimaCardPressStyle() }
}

/// Two-or-more-way segmented control. Selected = amber text on a faint amber tint; rest = muted. Fills the row
/// on iPhone; on iPad each segment stops at `maxSegmentWidth` and the control sits at the leading edge.
struct KimaSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.horizontalSizeClass) private var sizeClass

    static var maxSegmentWidth: CGFloat { 160 }

    var body: some View {
        segments
            .frame(maxWidth: sizeClass == .regular ? CGFloat(options.count) * Self.maxSegmentWidth : .infinity)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var segments: some View {
        HStack(spacing: KimaSpacing.xs) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Text(option.label.lowercased())
                    .font(KimaType.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(selected ? KimaColor.brand : KimaColor.textMuted)
                    .frame(maxWidth: .infinity, minHeight: KimaLayout.minTouchTarget)
                    .background {
                        if selected { segmentShape.fill(KimaColor.brandTint) }
                    }
                    .contentShape(segmentShape)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) { selection = option.value }
                    }
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    private var segmentShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
    }
}

/// Standard text-field chrome: neutral raised fill, hairline border, faint amber focus border, softened
/// `card` corners (desktop rounded inputs).
private struct KimaFieldModifier: ViewModifier {
    var focused: Bool
    func body(content: Content) -> some View {
        content
            .font(KimaType.headline)
            .foregroundStyle(KimaColor.textPrimary)
            .tint(KimaColor.brand)
            .padding(KimaSpacing.lg)
            .background(KimaColor.surfaceRaised, in: RoundedRectangle(cornerRadius: KimaRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: KimaRadius.card)
                    .strokeBorder(focused ? KimaColor.brand.opacity(0.4) : KimaColor.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func kimaField(focused: Bool = false) -> some View { modifier(KimaFieldModifier(focused: focused)) }
}

extension Text {
    /// Warm, clearly-visible placeholder text for a field's `prompt:`.
    static func kimaPrompt(_ text: String) -> Text {
        Text(text).foregroundColor(KimaColor.textSecondary)
    }
}

// MARK: - Seamless screen canvas

/// Standard screen canvas: opaque base + ambient wash, full-bleed, so every screen meets the top
/// edge the same way. Apply at a screen's root. Detail screens with an artwork hero sit on the same
/// ground and fade the hero into it (`kimaHeroGround`). Keep the nav bar background hidden so no
/// opaque bar brings back the edge.
private struct KimaScreenCanvas: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            KimaScreenGround()
            content
        }
    }
}

/// The canvas ground on its own (base + ambient wash, full-bleed), for screens that already
/// stack their content in a ZStack. Tab roots and pushed screens share it.
struct KimaScreenGround: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            KimaColor.base
            AmbientFieldBackdrop(palette: env.ambientPalette)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Apple Liquid Glass, for the FUNCTIONAL layer only (nav / controls / floating chrome) — never
    /// content, never dense text (HIG rule). Real `glassEffect` on iOS 26 so the vibe-lit content
    /// refracts through the chrome as it scrolls behind; `.ultraThinMaterial` fallback below.
    /// Never on a Button's label — on iOS 26 it takes the touch; put it in `.background { … .allowsHitTesting(false) }`.
    @ViewBuilder
    func kimaGlassChrome<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// The floating glass disc behind a top-corner icon (activity bell, vibe map bar), 44pt unless `size` says
    /// otherwise: glass sits behind the button so it never takes the touch, with one hairline edge.
    func kimaChromeDisc(size: CGFloat = KimaLayout.chromeDiscSize) -> some View {
        self
            .frame(width: size, height: size)
            .background { Circle().fill(Color.clear).kimaGlassChrome(in: Circle()).allowsHitTesting(false) }
            .overlay(Circle().strokeBorder(KimaColor.hairline, lineWidth: 1))
            .contentShape(Rectangle())
    }

    /// A bare outline for a control drawn straight on the vibe map, with no glass behind it: the strong
    /// hairline, amber while the control is on.
    func kimaOutline<S: InsettableShape>(_ shape: S, on: Bool = false) -> some View {
        overlay(shape.strokeBorder(on ? KimaColor.brand : KimaColor.hairlineStrong, lineWidth: 1))
    }

    /// The 44pt outline ring round a glyph on the vibe map (the rail's tools, the labels switch when off).
    func kimaOutlineRing(on: Bool = false) -> some View {
        frame(width: KimaLayout.chromeDiscSize, height: KimaLayout.chromeDiscSize)
            .kimaOutline(Circle(), on: on)
    }

    func kimaScreenCanvas() -> some View {
        modifier(KimaScreenCanvas())
    }
}


// MARK: - Entrance motion

/// Content rises + fades in on first appearance, staggered by `index` — feeds and rows *arrive*
/// in a gentle cascade instead of popping. One-shot per instance; respects Reduce Motion.
private struct KimaEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true; return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(Double(index) * 0.07)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// A gentle staggered rise+fade on first appearance. Pass the item's position for the stagger.
    func kimaEntrance(_ index: Int = 0) -> some View { modifier(KimaEntrance(index: index)) }
}

// MARK: - Screen-width clamp

/// Pins a screen-root scroll column (direct child of its ScrollView) to the viewport width measured at the shell root.
/// A vertical ScrollView centers content on its ideal width; horizontal rails report ideal = sum of children, so the
/// column centers on that inflated width and clips at both edges. The frame goes inside the ScrollView, with the width
/// measured outside it. `fixedSize(horizontal:)` must not be used: it proposes .infinity to children.
struct KimaViewportWidthModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.frame(width: env.viewportWidth > 0 ? env.viewportWidth : nil)
    }
}

extension View {
    func kimaViewportWidth() -> some View {
        modifier(KimaViewportWidthModifier())
    }
}
