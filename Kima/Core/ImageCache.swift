import ImageIO
import UIKit
import os

actor ImageCache {
    static let shared = ImageCache()
    // NSCache is internally thread-safe, so a synchronous nonisolated peek (`cachedImage`) is
    // safe alongside the actor-isolated store/clear. `nonisolated(unsafe)` opts this one
    // property out of actor isolation without wrapping every access in `await`.
    private nonisolated(unsafe) let cache = NSCache<NSString, UIImage>()
    /// Bytes of the images the cache holds now (adds on store, subtracts on eviction).
    private nonisolated let bytes = CachedBytes()
    private let session: URLSession

    // Configured once per session by AppEnvironment after the client + server are ready.
    private var serverHost: String? = nil
    private var authHeaderProvider: (@Sendable () async -> (field: String, value: String)?)? = nil

    /// In-flight downloads keyed like the cache. Concurrent callers for the same image share
    /// a single Task and receive the same result — one network request per image at a time.
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    init() {
        cache.countLimit = 200; cache.totalCostLimit = 50 * 1024 * 1024
        cache.delegate = bytes
        // Dedicated ephemeral session: no persistent disk cache, routes through
        // ServerTrustCoordinator for TOFU validation on self-signed server certs.
        let config = URLSessionConfiguration.ephemeral
        session = URLSession(configuration: config, delegate: ServerTrustCoordinator.shared, delegateQueue: nil)
    }

    /// Wires auth for cover-art requests. Only URLs whose host exactly matches `serverHost` (case-insensitive) get
    /// the header; external image hosts never do. `authHeader` runs on each cache miss, so it always reads the
    /// current credential and needs no re-configure on token refresh or login/logout. It returns nil with no credential.
    func configure(serverHost: String?, authHeader: @escaping @Sendable () async -> (field: String, value: String)?) {
        self.serverHost = serverHost
        self.authHeaderProvider = authHeader
    }

    /// The cache key: the URL, plus the size cap when the image is stored shrunk.
    private nonisolated static func key(_ url: URL, _ maxPixel: Int?) -> String {
        maxPixel.map { "\(url.absoluteString)#\($0)" } ?? url.absoluteString
    }

    /// Synchronous, non-isolated peek at the in-memory cache. Returns a resident image
    /// immediately (never downloads), or nil on a miss. Lets SwiftUI render an already-cached
    /// cover on the FIRST frame instead of after `fetch`'s `await` — which lands a frame late
    /// and makes freshly-shown art "pop in" during an entrance animation. Pair with `fetch`.
    nonisolated func cachedImage(for url: URL, maxPixel: Int? = nil) -> UIImage? {
        cache.object(forKey: Self.key(url, maxPixel) as NSString)
    }
    func store(_ img: UIImage, for url: URL) { store(img, forKey: url.absoluteString) }

    private func store(_ img: UIImage, forKey key: String) {
        let key = key as NSString
        if let old = cache.object(forKey: key) { bytes.remove(old) }
        bytes.add(img)
        cache.setObject(img, forKey: key, cost: CachedBytes.cost(of: img))
    }

    /// What "clear image cache" frees: the bytes of the images held in memory right now.
    nonisolated var storedBytes: Int { bytes.total }

    /// Clear all in-memory cached images and cancel any in-flight downloads.
    /// Called from Settings → Downloads → Clear Cache.
    func clearAll() {
        cache.removeAllObjects()
        bytes.reset()
        // In-flight Tasks self-retain, so they must be cancelled; the generation stamp below is the backstop that
        // keeps bytes landing after a clear out of the cache. Cancellation is not transparent to joiners: they
        // throw URLError .cancelled, render the placeholder this pass, and re-fetch on next appear.
        // Intentional: stale bytes after "clear cache" are worse.
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        generation += 1
    }

    /// Incremented by clearAll(); fetch compares it around the await so a
    /// clear during a download drops the result from the cache (not from the
    /// caller's hands — the image is valid, it is just pre-clear and stale).
    private var generation = 0

    /// Fetches an image from the in-memory cache or the network; concurrent callers for one URL share a Task.
    /// The header is attached only for `serverHost`. The cache key is `key(url, maxPixel)`; the token isn't in it.
    /// With `authenticated` false the header is never attached, even for our own host (the public share
    /// viewer's endpoints are unauthenticated and must not see the bearer token). `maxPixel` decodes the image
    /// shrunk to at most that many pixels on its longer side, for art from outside servers that comes at full size.
    func fetch(url: URL, authenticated: Bool = true, maxPixel: Int? = nil) async throws -> UIImage {
        let key = Self.key(url, maxPixel)
        if let cached = cache.object(forKey: key as NSString) { return cached }

        // Join an existing in-flight download rather than firing a duplicate request.
        if let existing = inFlight[key] { return try await existing.value }

        // Capture actor-isolated state before entering the unstructured Task so the
        // closure body is self-contained and Swift 6 strict-concurrency is satisfied.
        let host = serverHost
        let provider = authHeaderProvider
        let capturedSession = session
        let gen = generation  // clearAll() stamp — see clearAll

        let task = Task<UIImage, Error> {
            var request = URLRequest(url: url)
            // Attach auth only for our own server — never for external CDN/podcast/Deezer hosts,
            // and never when the caller opted out (the public share viewer).
            if authenticated,
               let host,
               url.host(percentEncoded: false)?.lowercased() == host.lowercased(),
               let provider,
               let (field, value) = await provider() {
                request.setValue(value, forHTTPHeaderField: field)
            }
            let (data, _) = try await capturedSession.data(for: request)
            if let maxPixel {
                guard let img = Self.downsampled(data, maxPixel: maxPixel) else { throw URLError(.cannotDecodeContentData) }
                return img
            }
            guard let img = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            // Force the lazy pixel decode here — off the main thread, on the actor's own
            // executor — instead of leaving it to rasterize synchronously during SwiftUI's
            // first draw. Falls back to the raw image if display prep
            // fails so a decode hiccup never turns into a dropped image.
            return await img.byPreparingForDisplay() ?? img
        }

        inFlight[key] = task
        defer { inFlight[key] = nil }
        // store() runs on the actor (no await between task.value return and the call),
        // guaranteeing the image lands in NSCache before inFlight[key] is cleared by defer.
        let img = try await task.value
        // A clearAll() mid-download stamps the generation: the bytes are valid
        // for this caller (return them) but pre-clear — never re-cache them.
        if generation == gen { store(img, forKey: key) }
        return img
    }

    /// `data` decoded at no more than `maxPixel` on its longer side (never enlarged), already decoded for display.
    private nonisolated static func downsampled(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceShouldCacheImmediately: true,
                       kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map { UIImage(cgImage: $0) }
    }
}

/// Running byte count of the images in an `NSCache`, kept current through its eviction callback.
/// Lock-guarded: NSCache evicts on whatever thread it likes.
private final class CachedBytes: NSObject, NSCacheDelegate, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [ObjectIdentifier: Int]())

    static func cost(of image: UIImage) -> Int { Int(image.size.width * image.size.height * 4) }

    var total: Int { state.withLock { $0.values.reduce(0, +) } }
    func add(_ image: UIImage) { state.withLock { $0[ObjectIdentifier(image)] = Self.cost(of: image) } }
    func remove(_ image: AnyObject) { _ = state.withLock { $0.removeValue(forKey: ObjectIdentifier(image)) } }
    func reset() { state.withLock { $0.removeAll() } }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        remove(obj as AnyObject)
    }
}
