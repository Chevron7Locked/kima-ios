import SwiftUI

// Kima design tokens, shared with the web app (brand #c98f3f, ink #f4eede, base #020104,
// line rgba(255,240,214,.08)). Amber is rare.

// MARK: - Color

/// Warm near-blacks for a violet cosmos stage. `brand` amber is the rare accent: primary action, one play control per
/// view, the active tab, progress and spinners; never a glow or gradient. `positive`/`caution`/`danger` are fixed,
/// meaning-bearing tokens, never swapped for `brand` or the player's mood accent. The adaptive mood glow
/// (`env.accent` / `FilamentAccent`) is scoped to the now-playing surface only.
enum KimaColor {
    static let base          = Color(hex: 0x020104)   // page canvas (canon --color-social-base)
    // Warm-tinted (violet bleed) so cards read as warm-dark IN the cosmos rather than neutral-grey
    // slabs — a deliberate mobile divergence from the web's neutral surface ramp.
    static let surface       = Color(hex: 0x0B0510).opacity(0.80)   // cards / panels (translucent — cosmos bleeds through; sheets/fields use surfaceRaised and stay solid)
    static let surfaceRaised = Color(hex: 0x140B18)   // nested wells / sheets / fields
    static let surfaceHover  = Color(hex: 0x1A1020)   // hover / secondary button
    static let surfaceActive = Color(hex: 0x201B13)   // selected / active
    static let vibeInk       = Color(hex: 0x08050E)   // vibe map mood labels drawn on the stars; callers set the opacity
    static let vibeInkWash   = vibeInk.opacity(0.42)   // the wash under vibe map labels and mood chips
    static let vibeLeader    = Color(hex: 0xF4EEDE).opacity(0.28)   // the vibe map's line from a selected star to its readout
    static let textPrimary   = Color(hex: 0xF4EEDE)   // headings / important labels (warm ink)
    // Grey ramp: every step clears 4.5:1 on `base` (canon --muted is ink at .60).
    static let textSecondary = Color(hex: 0xF4EEDE).opacity(0.75)   // ink at .75
    static let textMuted     = Color(hex: 0xF4EEDE).opacity(0.60)   // meta / captions (ink at .60)
    static let textFaint     = Color(hex: 0xF4EEDE).opacity(0.50)   // timestamps, dimmest meta
    // Brand accent — the single muted amber, RARE. Canon SSOT: --color-brand #c98f3f.
    static let brand         = Color(hex: 0xC98F3F)
    static let brandBright   = Color(hex: 0xD9A95C)   // brand-light (gradients, glows)
    static let brandDeep     = Color(hex: 0xA66E2E)   // brand-dark (pressed)
    static let onBrand       = Color(hex: 0x160A02)   // text and glyphs on an amber fill (canon --on-brand)
    static let brandTint     = brand.opacity(0.12)    // selected segment ground (canon SegmentedTabs)
    static let fillQuiet     = Color(hex: 0xFFF0D6).opacity(0.06)   // neutral secondary button / tag ground
    static let discGlass     = Color.black.opacity(0.55)   // dark-glass disc behind a play glyph over art or the page
    static let dangerFill    = Color(hex: 0x7C2E1F)   // destructive button fill (canon --aggr 72% into black)
    static let ambient       = Color(red: 119/255, green: 59/255, blue: 151/255)  // canon --ambient-rgb 119,59,151 — the violet cosmos bleed
    static let hairline      = Color(hex: 0xFFF0D6).opacity(0.08)   // canon --line rgba(255,240,214,.08)
    static let hairlineStrong = Color(hex: 0xFFF0D6).opacity(0.14)  // canon --line-2: rings drawn straight on the vibe map
    // Semantic — fixed, meaning-bearing; do not use for decorative / now-playing accents.
    static let positive      = Color(hex: 0x3D7A4E)   // deep low-chroma green — success / owned / online
    static let caution       = Color(hex: 0xB8863B)   // muted amber — offline / heads-up (distinct from brand)
    static let danger        = Color(hex: 0xEF4444)   // red-500 — destructive / insecure-connection
}

// MARK: - Typography

/// Type scale: one role per job, every role Dynamic-Type relative. Bricolage Grotesque is the voice for the hero
/// line, page titles, the single hero name on a detail screen, and the numbers that are the content; Montserrat
/// carries section headings, body, captions and meta. Sizes: 40 · 28 · 22 · 20 · 17 · 15 · 13 · 11 — 11 is the floor.
/// Figures add `.monospacedDigit()`. Lowercasing is done at call sites with `.lowercased()`; fonts cannot lowercase.
enum KimaType {

    /// The one poster line in the app, the Home greeting — Bricolage bold 40.
    static let hero = Font.custom("BricolageGrotesque-Bold", size: 40, relativeTo: .largeTitle)

    /// Page titles, sheet titles and the hero name on a detail screen — Bricolage bold 28.
    static let pageTitle = Font.custom("BricolageGrotesque-Bold", size: 28, relativeTo: .title)

    /// A lead sentence that is itself the content (the Stats summary line) — Bricolage medium 28.
    static let statement = Font.custom("BricolageGrotesque-Medium", size: 28, relativeTo: .title)

    /// Numbers and short findings that are the data (stat values, the vibe map's selected track) — Bricolage
    /// medium 22.
    static let figure = Font.custom("BricolageGrotesque-Medium", size: 22, relativeTo: .title2)

    /// Section headings — Montserrat semibold 20.
    static let section = Font.custom("Montserrat-SemiBold", size: 20, relativeTo: .title3)

    /// Card titles and controls — Montserrat semibold 17.
    static let headline = Font.custom("Montserrat-SemiBold", size: 17, relativeTo: .headline)

    /// Body copy — Montserrat regular 15.
    static let body = Font.custom("Montserrat-Regular", size: 15, relativeTo: .subheadline)

    /// Row titles and short emphasis — Montserrat semibold 15.
    static let bodyStrong = Font.custom("Montserrat-SemiBold", size: 15, relativeTo: .subheadline)

    /// Secondary lines, durations, small buttons — Montserrat medium 13.
    static let caption = Font.custom("Montserrat-Medium", size: 13, relativeTo: .footnote)

    /// Caption that needs weight (a small button, a selected chip) — Montserrat semibold 13.
    static let captionStrong = Font.custom("Montserrat-SemiBold", size: 13, relativeTo: .footnote)

    /// Counts, timestamps, tags and labels under icons — Montserrat medium 11, the smallest text the app sets.
    static let meta = Font.custom("Montserrat-Medium", size: 11, relativeTo: .caption2)

    /// Meta that needs weight — Montserrat semibold 11.
    static let metaStrong = Font.custom("Montserrat-SemiBold", size: 11, relativeTo: .caption2)

    /// The "kima" wordmark beside the mark. Sized to the mark it sits next to, so it takes an explicit size.
    static func wordmark(_ size: CGFloat) -> Font {
        Font.custom("BricolageGrotesque-SemiBold", size: size, relativeTo: .title)
    }

    /// Text drawn inside a fixed geometry (a label on the vibe map, a figure inside the key wheel), where the size
    /// comes from the drawing, not the reading scale. Not for ordinary text.
    static func fitted(_ size: CGFloat, bricolage: Bool = false) -> Font {
        .custom(bricolage ? "BricolageGrotesque-Regular" : "Montserrat-Medium", fixedSize: size)
    }
}

// MARK: - Spacing (4pt scale)

/// The 4pt scale and the rhythm built on it. Things that belong together always sit closer than the groups around
/// them: a pair < inside a tile < between tiles < heading to content < between sections.
///
/// | role                                                  | step      |
/// |-------------------------------------------------------|-----------|
/// | a text pair (title → subtitle, name → its line)       | xs  4     |
/// | small glyph → its label, icon over its label          | xs  4     |
/// | chip / tag inside (horizontal · vertical)             | sm · xs   |
/// | cover art → its label; a meta run (· separated)       | sm  8     |
/// | list row inside (vertical); control inside (vertical) | sm  8     |
/// | compact buttons in a row or grid (both ways)          | sm  8     |
/// | between tiles in a rail; grid columns                 | md  12    |
/// | section heading → its content                         | md  12    |
/// | screen side gutter                                    | lg  16    |
/// | between rows of a cover grid; panel inside            | xl  24    |
/// | between sections (KimaSectionHeader's top); between   | xxl 32    |
/// | two groups inside one section (station chips → moods) |           |
///
/// A literal is kept only for drawn geometry (chart cells, a hairline, a fixed badge) or an optical nudge, and says so.
enum KimaSpacing {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 16
    static let xl:   CGFloat = 24
    static let xxl:  CGFloat = 32
    static let huge: CGFloat = 48
}

enum KimaLayout {
    /// Smallest tappable area for any control (Apple's 44pt minimum); see `kimaHitTarget()`.
    static let minTouchTarget: CGFloat = 44

    /// Widest the content of a full-screen page gets on iPad; see `kimaReadableWidth()`.
    static let readableWidth: CGFloat = 720

    /// Narrowest a fitted rail or grid tile gets on regular width (`railFit`).
    static let railTileMin: CGFloat = 160
    /// Gap between fitted tiles: the screen grid's side inset, so a rail's next tile starts exactly at the edge.
    static let railGap: CGFloat = KimaSpacing.lg

    /// How many tiles of at least `railTileMin` fit across `width` inside the screen grid's side insets, `railGap`
    /// apart, and the width that makes them meet both insets exactly.
    static func railFit(width: CGFloat) -> (count: Int, tileWidth: CGFloat) {
        let inner = width - 2 * KimaSpacing.lg
        let count = max(1, Int((inner + railGap) / (railTileMin + railGap)))
        return (count, max(0, (inner - CGFloat(count - 1) * railGap) / CGFloat(count)))
    }

    /// How far a hero backdrop reaches past each side of the readable column to meet the screen edges.
    static func columnBleed(viewport: CGFloat) -> CGFloat {
        max(0, (viewport - readableWidth) / 2)
    }

    /// Side of the cover in a detail page's hero (`KimaDetailHero`) on a phone.
    static let heroCover: CGFloat = 140
    /// Side of a detail page's hero cover or artist photo on regular width.
    static let heroCoverRegular: CGFloat = 200

    /// Size of a floating glass disc that is its own touch target (a pushed page's back button, the vibe map's bar),
    /// the same size as the system back-button disc.
    static let chromeDiscSize: CGFloat = 44

    /// Size of the glass in the top corners of a tab's main page (the activity bell, Home's header pill): smaller than
    /// `chromeDiscSize`, so the bell clears the buttons under a page title. The bell's touch area stays 44pt.
    static let cornerDiscSize: CGFloat = 36

    /// Height of the floating row under the status bar (Home's header, a pushed page's back button): the disc and the
    /// 8pt above it.
    static let topChromeHeight: CGFloat = chromeDiscSize + KimaSpacing.sm

    /// The short soft edge at the bottom of the status bar, where scrolled content fades out before the clock.
    static let statusBarFade: CGFloat = 14
}

// MARK: - Radius (desktop ladder)

/// Corner-radius ladder: `image` for cover art and thumbnails, `card` for cards, panels,
/// sheets, toasts and fields, `hero` for large detail covers. Pills, buttons and play buttons
/// use `Capsule` / `Circle`, not a radius token.
enum KimaRadius {
    static let image:  CGFloat = 8    // cover-art tiles / thumbnails
    static let card:   CGFloat = 12   // cards, tiles, panels, sheets, toasts, fields
    static let hero:   CGFloat = 14   // large detail-hero covers
}

// MARK: - Helpers

extension Color {
    /// Build a color from a 0xRRGGBB hex literal in the sRGB space.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}
