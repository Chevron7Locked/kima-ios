import CoreImage
import SwiftUI
import UIKit

/// An image filling its frame, blurred once into a finished bitmap, so a scrolling page does not redraw the blur.
/// Edges are clamped, like `.blur(radius:opaque: true)`. Until the bitmap for this image is ready it shows the same blur
/// drawn live.
/// It blurs again when its width changes (rotation, iPad resizing); height changes (a hero stretching on pull-down)
/// scale the bitmap.
struct KimaPreblurredImage: View {
    let image: UIImage
    /// In points, as for `.blur(radius:)`.
    let radius: CGFloat
    /// How far the image is enlarged past filling the frame.
    var zoom: CGFloat = 1

    @State private var size: CGSize = .zero
    /// The finished blur and the image it was made from; a blur of an earlier image is never shown.
    @State private var blurred: (source: ObjectIdentifier, image: UIImage)?

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .overlay {
                if let blurred, blurred.source == ObjectIdentifier(image) {
                    Image(uiImage: blurred.image).resizable().scaledToFill()
                } else {
                    Image(uiImage: image).resizable().scaledToFill().scaleEffect(zoom).blur(radius: radius, opaque: true)
                }
            }
            .clipped()
            .task(id: TaskKey(image: ObjectIdentifier(image), radius: radius, zoom: zoom, width: size.width.rounded(),
                              sized: size.height > 0)) {
                guard size.width > 0, size.height > 0 else { return }
                let target = size, source = image, radius = radius, zoom = zoom
                let result = await Task.detached(priority: .userInitiated) {
                    KimaBlurRenderer.blur(source, filling: target, radius: radius, zoom: zoom)
                }.value
                // A newer image or width has started its own blur; this one is stale.
                guard !Task.isCancelled else { return }
                blurred = result.map { (ObjectIdentifier(source), $0) }
            }
    }

    private struct TaskKey: Equatable {
        let image: ObjectIdentifier
        let radius: CGFloat
        let zoom: CGFloat
        let width: CGFloat
        let sized: Bool
    }
}

/// A cover loaded by id and shown through `KimaPreblurredImage`. A cached cover shows on the first frame; while one
/// loads, or if it fails, it is the cover placeholder's colour.
struct KimaPreblurredCover: View {
    let coverId: String?
    let size: Int
    let radius: CGFloat
    var zoom: CGFloat = 1

    @Environment(AppEnvironment.self) private var env
    /// The loaded cover and the URL it came from; a cover for an earlier URL is never shown.
    @State private var image: (url: URL, image: UIImage)?

    private var url: URL? {
        guard let id = coverId, !id.isEmpty else { return nil }
        return CoverArtURL.url(base: env.server, coverId: id, size: size)
    }

    private var current: UIImage? {
        guard let url else { return nil }
        if let image, image.url == url { return image.image }
        return ImageCache.shared.cachedImage(for: url)
    }

    var body: some View {
        Group {
            if let shown = current {
                KimaPreblurredImage(image: shown, radius: radius, zoom: zoom)
            } else {
                KimaColor.surface
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = (try? await ImageCache.shared.fetch(url: url)).map { (url, $0) }
        }
    }
}

enum KimaBlurRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// `image` scaled to fill `size`, enlarged by `zoom` (points, drawn at one pixel per point: a blur this wide hides the difference)
    /// and blurred by `radius`. Nil if the image can't be read.
    static func blur(_ image: UIImage, filling size: CGSize, radius: CGFloat, zoom: CGFloat = 1) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let input = CIImage(cgImage: cg).oriented(orientation(image.imageOrientation))
        let scale = max(size.width / input.extent.width, size.height / input.extent.height) * zoom
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let crop = CGRect(x: scaled.extent.minX + (scaled.extent.width - size.width) / 2,
                          y: scaled.extent.minY + (scaled.extent.height - size.height) / 2,
                          width: size.width, height: size.height).integral
        let output = scaled.clampedToExtent().applyingGaussianBlur(sigma: Double(radius)).cropped(to: crop)
        guard let result = context.createCGImage(output, from: crop) else { return nil }
        return UIImage(cgImage: result)
    }

    private static func orientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
