import AVFoundation
import os

// MARK: - Advance prefetch
//
// `prepareStream(url:)` starts loading the next stream's asset while the current item plays; when the
// advance's URL matches, `load(url:)` builds the item from that warmed asset. No change on a miss.
extension PlaybackEngine {

    /// Warm the stream URL in the background: `load(.isPlayable)` opens the connection and fetches init data
    /// while the current track plays. The asset is kept in `prefetchedAsset`, and `load(url:)` builds the real
    /// `AVPlayerItem` from that same asset on a URL match. Overwrites any older prefetch.
    func prepareStream(url: URL) {
        let asset = AVURLAsset(url: url)
        // The Task closure retains the asset until loading settles; `prefetchedAsset`
        // retains it until the next load() consumes or discards it.
        Task { _ = try? await asset.load(.isPlayable) }
        prefetchedAsset = asset
        #if DEBUG
        logger.info("KIMA_AUDIO prefetch started")
        #endif
    }
}
