import SwiftUI
import UIKit
import XCTest
@testable import Kima

/// The artwork tile treatment (clip to a continuous rounded rect + 1pt hairline edge) renders the
/// pixels it promises, and renders EXACTLY what the hand-spelled pair it replaces rendered —
/// the primitive is convergence, not redesign, so equality with the old spelling IS the contract.
@MainActor
final class KimaArtworkTileTests: XCTestCase {

    /// A 40pt opaque red square over black at 1 px/pt, so every assertion below reads a single pixel.
    private func render<V: View>(@ViewBuilder _ content: () -> V) throws -> UIImage {
        let renderer = ImageRenderer(content: content().frame(width: 40, height: 40))
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage)
    }

    private func pixel(_ image: UIImage, _ x: Int, _ y: Int) throws -> (r: Int, g: Int, b: Int) {
        let source = try XCTUnwrap(image.cgImage)
        let cropped = try XCTUnwrap(source.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var buffer = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: 1, height: 1, bitsPerComponent: 8,
                                              bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(buffer[0]), Int(buffer[1]), Int(buffer[2]))
    }

    private func tile() throws -> UIImage {
        try render {
            Color(red: 1, green: 0, blue: 0)
                .frame(width: 40, height: 40)
                .kimaArtworkTile()
                .background(Color.black)
        }
    }

    /// The corners are clipped away — the black backing shows through where the square used to be.
    func testClipsAllFourCorners() throws {
        let image = try tile()
        for corner in [(0, 0), (39, 0), (0, 39), (39, 39)] {
            let p = try pixel(image, corner.0, corner.1)
            XCTAssertLessThan(p.r + p.g + p.b, 24, "corner \(corner) should be clipped to the black backing")
        }
    }

    /// The top edge carries the hairline: `KimaColor.hairline` (FFF0D6 at 8%) over red content is
    /// ≈ (255, 19, 17). Without the stroke this pixel would be pure red (g = b = 0).
    func testStrokesTheEdgeWithTheHairline() throws {
        let p = try pixel(try tile(), 20, 0)  // mid-run of the top edge, inside the straight segment
        XCTAssertGreaterThan(p.r, 200, "the hairline stays a light wash over the art, not a dark band")
        XCTAssertGreaterThan(p.g, 8, "no hairline on the edge (pure red)")
        XCTAssertGreaterThan(p.b, 5, "no hairline on the edge (pure red)")
        XCTAssertLessThan(p.g, 60, "edge tint is heavier than the 8% hairline")
    }

    /// The middle of the tile stays untouched artwork.
    func testKeepsTheArtworkInside() throws {
        let p = try pixel(try tile(), 20, 20)
        XCTAssertGreaterThan(p.r, 240)
        XCTAssertLessThan(p.g, 15)
        XCTAssertLessThan(p.b, 15)
    }

    /// Pixel-identical to the hand-spelled pair at every site's radius: the primitive is the same
    /// clip + hairline overlay, so a diff against the old spelling must be empty.
    func testMatchesTheHandSpelledPairAtEveryTokenRadius() throws {
        for radius in [KimaRadius.image, KimaRadius.hero] {
            let primitive = try render {
                Color(red: 1, green: 0, blue: 0)
                    .frame(width: 40, height: 40)
                    .kimaArtworkTile(cornerRadius: radius)
                    .background(Color.black)
            }
            let handSpelled = try render {
                Color(red: 1, green: 0, blue: 0)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(KimaColor.hairline, lineWidth: 1)
                    )
                    .background(Color.black)
            }
            let a = try XCTUnwrap(primitive.pngData())
            let b = try XCTUnwrap(handSpelled.pngData())
            XCTAssertEqual(a, b, "the primitive must render exactly the hand-spelled pair at radius \(radius)")
        }
    }
}
