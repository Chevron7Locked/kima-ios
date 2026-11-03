import SwiftUI

// MARK: - KimaSectionHeader

/// Section header: a lowercase title, an optional badge pill, and an optional trailing control
/// or "see all" link. Owns its horizontal padding, so call sites place it full-width.
struct KimaSectionHeader<Trailing: View>: View {

    let title: String
    /// Small badge pill shown after the title — e.g. "Last.fm", "Deezer".
    var badge: String? = nil
    /// If provided and no custom trailing view was given, a muted "See all" link with chevron appears.
    var onSeeAll: (() -> Void)? = nil

    private let trailingContent: Trailing
    /// True when a non-EmptyView trailing was supplied; gates the SEE ALL fallback.
    private let hasTrailing: Bool

    // MARK: - Initialisers

    /// No trailing view (most common — Trailing == EmptyView).
    init(
        title: String,
        badge: String? = nil,
        onSeeAll: (() -> Void)? = nil
    ) where Trailing == EmptyView {
        self.title      = title
        self.badge      = badge
        self.onSeeAll   = onSeeAll
        trailingContent = EmptyView()
        hasTrailing     = false
    }

    /// Generic `@ViewBuilder` trailing.  Preferred for new call sites.
    init(
        title: String,
        badge: String? = nil,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title      = title
        self.badge      = badge
        self.onSeeAll   = onSeeAll
        trailingContent = trailing()
        hasTrailing     = true
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: KimaSpacing.md) {

            // One line: the title wins width (layoutPriority) and scales down on narrow devices rather than wrapping.
            Text(title.lowercased())
                .font(KimaType.section)
                .foregroundStyle(KimaColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            if let badge = badge {
                KimaTag(text: badge.lowercased())
            }

            // Push the trailing slot to the right edge.
            Spacer(minLength: KimaSpacing.md)

            // Right slot: custom trailing takes priority over SEE ALL.
            if hasTrailing {
                trailingContent
            } else if let onSeeAll {
                Button(action: onSeeAll) {
                    HStack(spacing: KimaSpacing.xs) {
                        Text("see all")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .fixedSize()
                    .kimaHitTarget(growsLayout: false)
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
            }
        }
        // Section chrome owns its horizontal margin — call sites place it full-width.
        .padding(.horizontal, KimaSpacing.lg)
        // More space above the heading (between sections) than below it (heading to its content).
        .padding(.top, KimaSpacing.xxl)
        .padding(.bottom, KimaSpacing.md)
    }
}

// MARK: - KimaHairline

/// The 1pt horizontal hairline rule. Takes the full width it is offered.
struct KimaHairline: View {
    var body: some View {
        Rectangle().fill(KimaColor.hairline).frame(height: 1)
    }
}

// MARK: - KimaRail

/// Horizontal lazy scroll rail for card carousels. Leading inset matches the screen grid; the larger trailing inset
/// lets the next card peek so the rail never ends flush. Given a `tileWidth`, a rail on regular width instead fits a
/// whole number of tiles to its own width (`KimaLayout.railFit`) between equal side insets, with gaps as wide as the
/// insets so the next tile starts exactly at the edge, and scrolls a tile at a time. The content closure receives the
/// tile width to use (the given one on compact width).
struct KimaRail<Content: View>: View {
    var spacing: CGFloat = KimaSpacing.md
    private let tileWidth: CGFloat?
    private let content: (CGFloat) -> Content

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var railWidth: CGFloat = 0

    init(spacing: CGFloat = KimaSpacing.md, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        tileWidth = nil
        self.content = { _ in content() }
    }

    init(spacing: CGFloat = KimaSpacing.md, tileWidth: CGFloat, @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.spacing = spacing
        self.tileWidth = tileWidth
        self.content = content
    }

    var body: some View {
        if sizeClass == .regular, let tileWidth {
            fitted(compactWidth: tileWidth)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    content(tileWidth ?? 0)
                }
                // Leading aligns with screen grid; trailing peek creates editorial edge-tension.
                .padding(.leading, KimaSpacing.lg)
                .padding(.trailing, KimaSpacing.xl)
                .padding(.bottom, KimaSpacing.xs)
            }
        }
    }

    /// Whole tiles from inset to inset; the compact width stands in until the rail has been measured.
    private func fitted(compactWidth: CGFloat) -> some View {
        let width = railWidth > 0 ? KimaLayout.railFit(width: railWidth).tileWidth : compactWidth
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: KimaLayout.railGap) {
                content(width)
            }
            .scrollTargetLayout()
            .padding(.bottom, KimaSpacing.xs)
        }
        .contentMargins(.horizontal, KimaSpacing.lg, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { railWidth = $0 }
    }
}
