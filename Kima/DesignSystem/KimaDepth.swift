import SwiftUI
import UIKit

// Depth primitives for cards on the near-black stage: one soft drop shadow
// (`kimaSleeveElevation`) and a near-flat card face (`kimaPlate`).

// MARK: - Sleeve elevation

/// Shared card elevation: one soft drop shadow so a cover lifts off the stage.
struct KimaSleeveElevation: ViewModifier {
    var cornerRadius: CGFloat
    var shadowOpacity: Double = 0.85

    func body(content: Content) -> some View {
        // Soft and grounded, never heavy or skeuomorphic (effective black opacity ≈ 0.42 at the default).
        content.kimaShapeShadow(cornerRadius: cornerRadius, opacity: shadowOpacity * 0.5, radius: 16, y: 8)
    }
}

extension View {
    /// Apply the shared card elevation (one soft drop shadow) to an already-clipped/rounded cover
    /// or surface. Pass the SAME `cornerRadius` the surface is clipped to.
    func kimaSleeveElevation(cornerRadius: CGFloat) -> some View {
        modifier(KimaSleeveElevation(cornerRadius: cornerRadius))
    }

    /// A black drop shadow cast by the view's rounded-rectangle outline, drawn behind it from that outline alone.
    /// It is a pre-drawn image stretched to the view's size: no pass over the content above it while the page
    /// scrolls, and no extra view per card. Use it on rounded artwork and cards in lists and rails; the view should be
    /// at least `2 × (cornerRadius + radius) + 3` points on each side.
    func kimaShapeShadow(cornerRadius: CGFloat, opacity: Double, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        let shadow = ShapeShadowImage.make(cornerRadius: cornerRadius, opacity: opacity, radius: radius)
        return background {
            Image(uiImage: shadow.image)
                .resizable(capInsets: EdgeInsets(top: shadow.cap, leading: shadow.cap,
                                                  bottom: shadow.cap, trailing: shadow.cap),
                           resizingMode: .stretch)
                .padding(-shadow.margin)
                .offset(x: x, y: y)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Stretchable shadow images, one per corner radius, opacity and blur. The image is the shadow of a rounded square
/// with `margin` of blur around it; its edges and corners stay fixed when stretched, and only straight runs (where
/// the shadow is uniform along the edge) are repeated.
@MainActor
private enum ShapeShadowImage {
    struct Key: Hashable {
        let cornerRadius: CGFloat
        let opacity: Double
        let radius: CGFloat
    }

    struct Rendered {
        let image: UIImage
        /// How far the blur reaches past the shape, in points.
        let margin: CGFloat
        /// The fixed border on each side of the image, in points.
        let cap: CGFloat
    }

    private static var cache: [Key: Rendered] = [:]

    static func make(cornerRadius: CGFloat, opacity: Double, radius: CGFloat) -> Rendered {
        let key = Key(cornerRadius: cornerRadius, opacity: opacity, radius: radius)
        if let hit = cache[key] { return hit }
        // A Core Graphics blur of `radius` matches SwiftUI's `.shadow(radius:)` and reaches about `radius` past the
        // shape.
        let margin = ceil(radius) + 1
        let cap = margin + cornerRadius + margin
        let side = 2 * cap + 1
        let shape = CGRect(x: margin, y: margin, width: side - 2 * margin, height: side - 2 * margin)
        let format = UIGraphicsImageRendererFormat.preferred()
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            // The shape is filled far off the canvas and only its shadow lands on it. Shadow offset and blur are in
            // pixels, not points.
            let away = side * 2
            cg.setShadow(offset: CGSize(width: away * format.scale, height: 0), blur: radius * format.scale,
                         color: UIColor.black.withAlphaComponent(opacity).cgColor)
            cg.addPath(Path(roundedRect: shape.offsetBy(dx: -away, dy: 0), cornerRadius: cornerRadius,
                            style: .continuous).cgPath)
            cg.fillPath()
        }
        let rendered = Rendered(image: image, margin: margin, cap: cap)
        cache[key] = rendered
        return rendered
    }
}

// MARK: - Plate surface (top-lit physical card face)

extension LinearGradient {
    /// Card face: a near-flat step from `surfaceRaised` to `surface`.
    static let kimaPlate = LinearGradient(
        colors: [KimaColor.surfaceRaised, KimaColor.surface],
        startPoint: .top, endPoint: .bottom
    )
}
