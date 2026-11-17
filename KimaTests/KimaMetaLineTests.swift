import SwiftUI
import UIKit
import XCTest
@testable import Kima

/// The job-row meta line (meta facts separated by hairline-muted bullets) renders EXACTLY what the
/// hand-spelled HStacks it replaces at the three job rows rendered — the primitive is convergence,
/// not redesign, so equality with the old spelling IS the contract (precedent: KimaArtworkTileTests).
@MainActor
final class KimaMetaLineTests: XCTestCase {

    /// A wide-enough strip so text lays out identically in both spellings; black backing so
    /// antialiased glyph edges are byte-comparable.
    private func render<V: View>(@ViewBuilder _ content: () -> V) throws -> Data {
        let renderer = ImageRenderer(content: content().frame(width: 260, height: 18).background(Color.black))
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage).pngData() ?? Data()
    }

    /// The verified hand-spelled spelling (HistoryRow's meta line, without its Label):
    /// meta font, textMuted, KimaSpacing.xs gaps, a literal "•" between the facts.
    private func handSpelled(_ facts: [String]) -> some View {
        HStack(spacing: KimaSpacing.xs) {
            ForEach(facts.indices, id: \.self) { i in
                if i > 0 {
                    Text("•").font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
                }
                Text(facts[i]).font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
            }
        }
    }

    /// Two facts get one bullet between them — pixel-for-pixel the hand-spelled row.
    func testTwoFactsGetOneBulletBetweenThem() throws {
        let primitive = try render {
            KimaMetaLine {
                Text("queued")
                Text("2m ago")
            }
        }
        let old = try render { handSpelled(["queued", "2m ago"]) }
        XCTAssertEqual(primitive, old, "two facts must render the hand-spelled 'a • b'")
    }

    /// A lone fact gets no bullet at all — the line is just the fact in the meta voice.
    func testOneFactGetsNoBullet() throws {
        let primitive = try render {
            KimaMetaLine {
                Text("queued")
            }
        }
        let old = try render {
            Text("queued").font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
        }
        XCTAssertEqual(primitive, old, "a single fact must render as a bare meta Text")
    }

    /// An `if`-fact carries its separator inside its own optionality (ActiveDownloadRow's
    /// optional statusText): present it renders "a • b • c", absent "a • c" — the bullet of an
    /// absent fact must vanish with it, leaving no orphan.
    func testConditionalFactTakesItsBulletWithIt() throws {
        let show = true
        let shown = try render {
            KimaMetaLine {
                Text("queued")
                if show { Text("searching lidarr") }
                Text("2m ago")
            }
        }
        let oldShown = try render { handSpelled(["queued", "searching lidarr", "2m ago"]) }
        XCTAssertEqual(shown, oldShown, "a present optional fact must render 'a • b • c'")

        let hide = false
        let hidden = try render {
            KimaMetaLine {
                Text("queued")
                if hide { Text("searching lidarr") }
                Text("2m ago")
            }
        }
        let oldHidden = try render { handSpelled(["queued", "2m ago"]) }
        XCTAssertEqual(hidden, oldHidden, "an absent optional fact must leave no orphan bullet")
    }

    /// The type→icon mapping (the one place it is spelled): "album" is a disc, everything
    /// else a mic — the mapping ActiveDownloadRow and HistoryRow hand-spelled verbatim.
    func testJobTypeSymbolMapping() {
        XCTAssertEqual(JobType.symbol(for: "album"), "opticaldisc")
        XCTAssertEqual(JobType.symbol(for: "artist"), "music.mic")
        XCTAssertEqual(JobType.symbol(for: "podcast"), "music.mic")
    }

    /// The label composite renders exactly the hand-spelled Label: title + icon, meta, muted.
    func testJobTypeLabelMatchesTheHandSpelledLabel() throws {
        let primitive = try render { KimaJobTypeLabel(type: "album") }
        let old = try render {
            // The old hand-spelling resolved "album" to opticaldisc. The expected value is
            // spelled independently of JobType so a mapping change reddens this test.
            Label("album", systemImage: "opticaldisc")
                .font(KimaType.meta)
                .foregroundStyle(KimaColor.textMuted)
                .labelStyle(.titleAndIcon)
        }
        XCTAssertEqual(primitive, old, "the type label must render the hand-spelled Label")
    }

    /// The job-row title block: captionStrong over textPrimary — the four-line block the three
    /// rows each spelled, line limit the only variant.
    func testTitleModifierMatchesHandSpelledTitle() throws {
        let primitive = try render { Text("ok computer").kimaJobRowTitle(lineLimit: 1) }
        let old = try render {
            Text("ok computer")
                .font(KimaType.captionStrong)
                .foregroundStyle(KimaColor.textPrimary)
                .lineLimit(1)
        }
        XCTAssertEqual(primitive, old, "the title modifier must render the hand-spelled block")
    }

    /// A LEADING `if`-fact gets no leading bullet — it bullets trailing, and the fact after it
    /// suppresses its own. Absent, its bullet is gone with it: never "• a".
    func testLeadingConditionalFactBulletsTrailing() throws {
        let show = true
        let shown = try render {
            KimaMetaLine {
                if show { Text("starting") }
                Text("2m ago")
            }
        }
        let oldShown = try render { handSpelled(["starting", "2m ago"]) }
        XCTAssertEqual(shown, oldShown, "a leading present fact must render 'x • a', never '• x a'")

        let hide = false
        let hidden = try render {
            KimaMetaLine {
                if hide { Text("starting") }
                Text("2m ago")
            }
        }
        let oldHidden = try render {
            Text("2m ago").font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
        }
        XCTAssertEqual(hidden, oldHidden, "an absent leading fact must leave the bare next fact")
    }

    /// The status-color variant stays a call-site parameter: a colored fact keeps its color
    /// while bullets and plain facts keep the line's inherited muted voice.
    func testStatusColoredFactKeepsItsColor() throws {
        let primitive = try render {
            KimaMetaLine {
                Text("processing").foregroundStyle(KimaColor.textPrimary)
                Text("2m ago")
            }
        }
        let old = try render {
            HStack(spacing: KimaSpacing.xs) {
                Text("processing").font(KimaType.meta).foregroundStyle(KimaColor.textPrimary)
                Text("•").font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
                Text("2m ago").font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
            }
        }
        XCTAssertEqual(primitive, old, "a call-site color must win over the line's muted default")
    }
}
