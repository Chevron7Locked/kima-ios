import XCTest
import SwiftUI
@testable import Kima

final class VibeMoodLabelTests: XCTestCase {

    func testSevenLabels() {
        XCTAssertEqual(VibeMoodPalette.labels, [
            "moodHappy": "upbeat", "moodSad": "melancholic", "moodRelaxed": "calm",
            "moodAggressive": "intense", "moodParty": "energetic",
            "neutral": "no single mood", "unanalyzed": "not analysed yet",
        ])
        XCTAssertEqual(VibeMoodPalette.moodKeys.count, 5)
    }

    func testBareServerNamesResolve() {
        XCTAssertEqual(VibeMoodPalette.label(for: "happy"), "upbeat")
        XCTAssertTrue(VibeMoodPalette.isMood("aggressive"))
        XCTAssertFalse(VibeMoodPalette.isMood("neutral"))
    }

    func testMapMoodsUseTheWebMoodTokens() {
        let hex = ["moodHappy": 0xe5a74b, "moodSad": 0x7e5c8e, "moodRelaxed": 0x529796,
                   "moodAggressive": 0xc14c35, "moodParty": 0xb65e8b]
        for (key, value) in hex {
            XCTAssertEqual(srgbHex(VibeMoodPalette.linearColour(for: key)!), UInt32(value), key)
        }
        XCTAssertEqual(VibeMoodPalette.linearColour(for: "happy"), VibeMoodPalette.linearColour(for: "moodHappy"))
    }

    func testMapSetIsTheWebHexes() {
        let web: [String: UInt32] = ["moodHappy": 0xe5a74b, "moodSad": 0x7e5c8e, "moodRelaxed": 0x529796,
                                     "moodAggressive": 0xc14c35, "moodParty": 0xb65e8b,
                                     "neutral": 0xa3a3a3, "unanalyzed": 0x606068]
        XCTAssertEqual(Set(VibeMoodPalette.mapColors.keys), Set(web.keys))
        for (key, hex) in web { XCTAssertEqual(packed(VibeMoodPalette.mapColors[key]!), hex, key) }
        XCTAssertEqual(VibeMoodPalette.mapColor(for: "happy"), VibeMoodPalette.mapColor(for: "moodHappy"))
    }

    func testGradientsUseTheSameWebTokensAsTheMap() {
        // Radio and mood-mixer gradients read the v1 token table — the legacy bright 7-mood
        // table (with acoustic/electronic) is gone. Dropped moods fall back to neutral.
        func pair(_ key: String) -> (Color, Color) { VibeMoodPalette.gradient(for: key) }
        XCTAssertEqual(pair("happy").0.description, pair("moodHappy").0.description)
        XCTAssertEqual(pair("moodElectronic").0.description, pair("neutral").0.description)
        XCTAssertEqual(pair("moodAcoustic").0.description, pair("neutral").0.description)
    }

    private func packed(_ c: (r: Double, g: Double, b: Double)) -> UInt32 {
        UInt32(c.r) << 16 | UInt32(c.g) << 8 | UInt32(c.b)
    }

    /// Inverse of `VibeMapStyle.linear(hex:)`: linear-light back to 0xRRGGBB, rounding each channel.
    private func srgbHex(_ c: SIMD3<Float>) -> UInt32 {
        func enc(_ v: Float) -> UInt32 {
            let x = max(0, min(1, v))
            let s = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            return UInt32((max(0, min(1, s)) * 255).rounded())
        }
        return enc(c.x) << 16 | enc(c.y) << 8 | enc(c.z)
    }
}
