import AVFoundation
import Foundation

/// Serves the player a FLAC that starts mid-track: a synthesized header (`FLACLayout.header`)
/// followed by the real stream's frames from `start.byte` on, fetched from the server by range as
/// the player asks for them (the bytes are the original's, untouched — no re-encode). The player
/// plays this from its first frame, so where it is in the track is `start.sample` plus its own time.
final class FLACTailLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "kima-flac"

    let source: URL
    let start: FLACStart
    private let header: Data
    private let fileLength: Int
    private let queue = DispatchQueue(label: "com.chevron7locked.kima.flac-tail")
    /// The engine's session, from the session factory: the app's posture, certificate trust included.
    private let session: URLSession
    /// In-flight server reads, by task, with the player request each one fills.
    private var pending: [Int: (request: AVAssetResourceLoadingRequest, task: URLSessionDataTask)] = [:]

    /// Bytes in the served file: the new header, then the original from `start.byte` to its end.
    var length: Int { header.count + fileLength - start.byte }

    init(source: URL, stream: FLACStream, start: FLACStart, session: URLSession) {
        self.source = source
        self.start = start
        self.header = stream.layout.header(startingAt: start.sample)
        self.fileLength = stream.fileLength
        self.session = session
        super.init()
    }

    /// The item this served is gone: its reads are no use to anyone.
    deinit { pending.values.forEach { $0.task.cancel() } }

    /// An asset over the served file. The asset holds its loader weakly: keep this object alive as
    /// long as the asset plays.
    func makeAsset() -> AVURLAsset {
        let asset = AVURLAsset(url: URL(string: "\(Self.scheme)://stream/track.flac")!)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ loader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        if let info = request.contentInformationRequest {
            info.contentType = "org.xiph.flac"
            info.contentLength = Int64(length)
            info.isByteRangeAccessSupported = true
        }
        guard let dataRequest = request.dataRequest else { request.finishLoading(); return true }
        var offset = Int(dataRequest.requestedOffset)
        let end = dataRequest.requestsAllDataToEndOfResource
            ? length : min(length, offset + dataRequest.requestedLength)
        if offset < header.count {
            dataRequest.respond(with: header.subdata(in: offset..<min(end, header.count)))
            offset = header.count
        }
        guard offset < end else { request.finishLoading(); return true }

        // The rest is the original file shifted by a constant: served byte n is file byte n - header + start.
        let shift = start.byte - header.count
        var read = URLRequest(url: source)
        read.setByteRange((offset + shift)..<(end + shift))
        let task = session.dataTask(with: read)
        task.delegate = Relay(self, queue: queue)
        pending[task.taskIdentifier] = (request, task)
        task.resume()
        return true
    }

    func resourceLoader(_ loader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        guard let id = pending.first(where: { $0.value.request === request })?.key else { return }
        pending.removeValue(forKey: id)?.task.cancel()
    }

    // MARK: - Server reads (on `queue`, like the loader callbacks)

    fileprivate func received(_ response: URLResponse, task: URLSessionTask) -> Bool {
        guard (response as? HTTPURLResponse)?.statusCode == 206 else {
            pending.removeValue(forKey: task.taskIdentifier)?.request.finishLoading(with: URLError(.badServerResponse))
            return false
        }
        return true
    }

    fileprivate func received(_ data: Data, task: URLSessionTask) {
        pending[task.taskIdentifier]?.request.dataRequest?.respond(with: data)
    }

    fileprivate func finished(_ task: URLSessionTask, error: Error?) {
        guard let request = pending.removeValue(forKey: task.taskIdentifier)?.request else { return }
        if let error { request.finishLoading(with: error) } else { request.finishLoading() }
    }
}

/// One read's delegate (the task's own, so the session's trust delegate still answers challenges):
/// hands the read to the loader on its queue, holding it weakly so a read never keeps it alive.
private final class Relay: NSObject, URLSessionDataDelegate {
    weak var loader: FLACTailLoader?
    let queue: DispatchQueue
    init(_ loader: FLACTailLoader, queue: DispatchQueue) { self.loader = loader; self.queue = queue }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        queue.async { [weak loader] in
            completionHandler(loader?.received(response, task: dataTask) == true ? .allow : .cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.async { [weak loader] in loader?.received(data, task: dataTask) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.async { [weak loader] in loader?.finished(task, error: error) }
    }
}
