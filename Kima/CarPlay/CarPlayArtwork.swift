import CarPlay
import UIKit

// MARK: - CarPlayArtwork
//
// CarPlay-sized cover art on top of the shared `ImageCache`, downscaled so list rows never carry a full-resolution
// decode. Art loads async and is applied after the row is visible; `placeholder` fills the gap.

/// MainActor surface: template/list-item types are UI-actor isolated, so anything that touches
/// `CPListItem`, `CPInterfaceController`, or builds the on-screen placeholder lives here.
@MainActor
enum CarPlayArtwork {

    /// Target point size for row art — roughly 2x the phone list-row thumbnail (44pt),
    /// matching the guidance to size for the car display's scale, not the phone's.
    static let targetPointSize: CGFloat = 88

    /// Generic glyph shown while art loads or when a row has no cover id at all.
    static let placeholder = UIImage(systemName: "music.note") ?? UIImage()

    /// Pixel-accurate target size for this interface controller's display, clamped to whatever
    /// `CPListItem.maximumImageSize` actually allows (varies by head unit / entitlement tier).
    static func targetSize(for interfaceController: CPInterfaceController) -> CGSize {
        let scale = interfaceController.carTraitCollection.displayScale
        let pointSize = min(
            targetPointSize,
            CPListItem.maximumImageSize.width,
            CPListItem.maximumImageSize.height
        )
        let side = max(pointSize, 1) * max(scale, 1)
        return CGSize(width: side, height: side)
    }

    /// Target size for `CPListImageRowItem` shelf art: the larger `CPListImageRowItem.maximumImageSize`, not the small
    /// `CPListItem.maximumImageSize` row-icon clamp. That property is deprecated in iOS 26 but works at the iOS 18
    /// deployment target (see CarPlayCoverShelf.swift).
    static func shelfImageSize(for interfaceController: CPInterfaceController) -> CGSize {
        let scale = interfaceController.carTraitCollection.displayScale
        let maxSize = CPListImageRowItem.maximumImageSize
        let pointSide = max(min(maxSize.width, maxSize.height), 1)
        let side = pointSide * max(scale, 1)
        return CGSize(width: side, height: side)
    }
}

// MARK: - Off-main-actor fetch + downscale
// Not a member of the `@MainActor CarPlayArtwork` enum, so the download and resize run off the UI actor.
/// Fetch + downscale a cover image for `coverId`. Returns nil on any failure; callers fall back to
/// `CarPlayArtwork.placeholder`.
func loadCarPlayArtwork(coverId: String, server: KimaServer, size: CGSize) async -> UIImage? {
    guard let url = CoverArtURL.url(base: server, coverId: coverId, size: Int(size.width)) else {
        return nil
    }
    return await loadCarPlayArtwork(url: url, size: size)
}

/// Fetch + downscale the image at `url`. Returns nil on any fetch failure.
func loadCarPlayArtwork(url: URL, size: CGSize) async -> UIImage? {
    guard let image = try? await ImageCache.shared.fetch(url: url) else { return nil }
    // preparingThumbnail is safe off the main thread and is the Apple-recommended way to
    // downscale an already-decoded image without hand-rolling a UIGraphicsImageRenderer pass.
    return image.preparingThumbnail(of: size) ?? image
}

// MARK: - Attaching artwork to list rows

/// Kick off an async cover-art fetch for `item` and apply it in place once it lands.
/// No-ops immediately when `coverId` is nil/empty — the row keeps its placeholder image.
/// Not cancellation-tracked: worst case a late image lands on a row that's since scrolled off
/// or been discarded, which is harmless (no crash, no stale data shown to the user).
@MainActor
func attachArtwork(to item: CPListItem, coverId: String?, env: AppEnvironment, interfaceController: CPInterfaceController) {
    guard let coverId, !coverId.isEmpty else { return }
    let size = CarPlayArtwork.targetSize(for: interfaceController)
    let server = env.server
    Task { @MainActor in
        guard let image = await loadCarPlayArtwork(coverId: coverId, server: server, size: size) else { return }
        item.setImage(image)
    }
}


/// URL-sourced variant: long-form now-playing artwork arrives pre-resolved
/// (`LongFormNowPlayingMeta.coverURL`), so this skips the `CoverArtURL` build step.
@MainActor
func attachArtwork(to item: CPListItem, url: URL, interfaceController: CPInterfaceController) {
    let size = CarPlayArtwork.targetSize(for: interfaceController)
    Task { @MainActor in
        guard let image = await loadCarPlayArtwork(url: url, size: size) else { return }
        item.setImage(image)
    }
}
