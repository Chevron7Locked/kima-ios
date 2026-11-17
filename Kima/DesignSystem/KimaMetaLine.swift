import SwiftUI

// MARK: - Job meta line

/// One line of `meta`-font facts separated by the app's hairline-muted "•" — the shape every
/// job row (active downloads, download history, imports) puts under its title. Facts are the
/// builder's children in reading order; the line inserts the separators itself, so call sites
/// never spell `Text("•")`. Everything inherits `KimaType.meta` and `textMuted`; a fact that
/// says something louder (a status color) overrides at the call site.
struct KimaMetaLine<Content: View>: View {
    @ViewBuilder private var content: Content

    init(@KimaMetaLineBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .font(KimaType.meta)
            .foregroundStyle(KimaColor.textMuted)
    }
}

/// The separator KimaMetaLine draws: a middle dot in the line's own voice — the meta font and
/// muted color are inherited from the container, not re-spelled here.
enum KimaMetaLineSeparator {
    static var view: some View {
        Text("•")
    }
}

/// Builds a `KimaMetaLine`: every child is one fact, and the builder threads the shared bullet
/// between successive facts. An `if`-fact carries its bullet inside its own optionality — an
/// absent fact takes its bullet with it, and a leading `if`-fact bullets trailing (the fact
/// after it suppresses its own leading bullet for that case), so the line never shows an orphan
/// separator. Supported grammar: plain facts plus at most the occasional `if`-fact, never two
/// adjacent — all three job rows fit; adjacent optionals are a documented non-goal.
@resultBuilder
enum KimaMetaLineBuilder {
    /// Where a fact sits on the line.
    struct Position {
        let isFirst: Bool
        let isLast: Bool
        /// True directly after an `if`-fact in leading position, which already trailed its
        /// bullet and must not get a second one.
        let afterJoined: Bool
    }

    /// The builder's one currency: every builder method takes and returns `Fact`, so the
    /// chain the compiler synthesizes at a call site never crosses an opaque type and never
    /// has to infer a type parameter from a chain result (both defeat inference at
    /// `if let`-condition sites — ActiveDownloadRow). Raw `View` arguments are adopted by the
    /// generic methods, which use their `V` only in direct `@ViewBuilder` helper calls
    /// (`AnyView` on a bare `V?` and nested plain functions fail the same way).
    struct Fact: View {
        /// The fact alone: for an `if`-fact, the fact's own optionality.
        let bare: AnyView
        /// "• fact" — inside an `if`-fact's optionality; the bullet rides with the fact.
        let withLeadingBullet: AnyView
        /// "fact •" — minted for `if`-facts only, drawn at leading position, where a leading
        /// bullet would orphan if the fact is absent.
        let withTrailingBullet: AnyView?
        let joined: Bool

        init(bare: AnyView, withLeadingBullet: AnyView,
             withTrailingBullet: AnyView? = nil, joined: Bool = false) {
            self.bare = bare
            self.withLeadingBullet = withLeadingBullet
            self.withTrailingBullet = withTrailingBullet
            self.joined = joined
        }

        func render(_ at: Position) -> AnyView {
            if joined {
                // withTrailingBullet is nil only for plain facts: every joined Fact is minted
                // by buildOptional below, which sets it.
                return at.isFirst ? (at.isLast ? bare : withTrailingBullet!) : withLeadingBullet
            }
            return (!at.isFirst && !at.afterJoined) ? withLeadingBullet : bare
        }

        /// A line's sole fact is position 0 with nothing after it: the bare spelling.
        var body: some View {
            bare
        }
    }

    static func buildExpression<V: View>(_ view: V) -> Fact {
        Fact(bare: AnyView(view),
             withLeadingBullet: AnyView(leadingBody(view)))
    }

    static func buildOptional<V: View>(_ view: V?) -> Fact {
        joined(bare: AnyView(bareBody(view)),
               leading: AnyView(leadingBody(view)),
               trailing: AnyView(trailingBody(view)))
    }

    /// The chain-argument spelling (`buildOptional(buildBlock(buildExpression(...)))`): the
    /// concrete overload exact-matches the `Fact` the chain already produced, so `V` never
    /// enters inference at the call site at all. The compiler demands BOTH signatures, so the
    /// overloads' shared shape lives in `joined`; the three `*Body` calls are per-signature
    /// plumbing (`V` must stay consumed inside a builder method).
    /// NOT `buildOptional<Fact>(view)`: an explicit specialization does not bypass the
    /// concrete overload's exact match — that delegation is infinite recursion, compiled
    /// cleanly by build-for-testing and crashed at runtime by the two `if`-fact tests.
    static func buildOptional(_ view: Fact?) -> Fact {
        joined(bare: AnyView(bareBody(view)),
               leading: AnyView(leadingBody(view)),
               trailing: AnyView(trailingBody(view)))
    }

    private static func joined(bare: AnyView, leading: AnyView, trailing: AnyView) -> Fact {
        Fact(bare: bare, withLeadingBullet: leading, withTrailingBullet: trailing, joined: true)
    }

    /// The non-optional twin of `leadingBody` below — the bare/leading/trailing trio named by
    /// position; a plain fact's leading form needs no optionality envelope.
    @ViewBuilder
    private static func leadingBody<V: View>(_ view: V) -> some View {
        KimaMetaLineSeparator.view
        view
    }

    @ViewBuilder
    private static func bareBody<V: View>(_ view: V?) -> some View {
        if let view {
            view
        }
    }

    @ViewBuilder
    private static func leadingBody<V: View>(_ view: V?) -> some View {
        if let view {
            KimaMetaLineSeparator.view
            view
        }
    }

    @ViewBuilder
    private static func trailingBody<V: View>(_ view: V?) -> some View {
        if let view {
            view
            KimaMetaLineSeparator.view
        }
    }

    /// One-statement blocks (an `if`-body) must round-trip as the Fact itself — the identity
    /// overload SwiftUI's ViewBuilder keeps for the same reason; the variadic one below is
    /// what composes a line.
    static func buildBlock(_ fact: Fact) -> Fact {
        fact
    }

    static func buildBlock(_ facts: Fact...) -> Fact {
        // A line's bare and leading forms are one view: a composite self-separates (the
        // bullets ride inside each fact's render), so there is nothing to add out front.
        let line = AnyView(line(facts))
        return Fact(bare: line, withLeadingBullet: line)
    }

    private static func line(_ facts: [Fact]) -> some View {
        HStack(spacing: KimaSpacing.xs) {
            ForEach(facts.indices, id: \.self) { i in
                facts[i].render(Position(
                    isFirst: i == 0,
                    isLast: i == facts.count - 1,
                    afterJoined: i == 1 && facts[0].joined
                ))
            }
        }
    }
}

// MARK: - Job row title

extension View {
    /// The title block every job row shares over its `KimaMetaLine`: captionStrong over
    /// textPrimary. The rows' only variant is how many lines the title may take.
    func kimaJobRowTitle(lineLimit: Int = 1) -> some View {
        font(KimaType.captionStrong)
            .foregroundStyle(KimaColor.textPrimary)
            .lineLimit(lineLimit)
    }
}

/// A job's type as a meta-line fact: its label text beside the `JobType` glyph — the Label
/// the download and history rows each used to spell, mapping and all.
struct KimaJobTypeLabel: View {
    let type: String

    var body: some View {
        Label(type, systemImage: JobType.symbol(for: type))
            .font(KimaType.meta)
            .foregroundStyle(KimaColor.textMuted)
            .labelStyle(.titleAndIcon)
    }
}
