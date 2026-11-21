import AVFoundation
import MediaToolbox
@testable import Kima

// A FLAC that says where it is: the left channel's 24-bit sample value IS the sample index, so a tap
// on the playing item reads the exact position being heard, independent of what the player reports.
// The right channel is noise whose loudness swells and fades, so the bitrate varies along the file
// the way music's does (a constant bitrate would let a byte-linear seek estimate land right).

enum FLACClockFixture {
    static let sampleRate = 22_050.0

    /// Writes the fixture once per test run (the encode takes about a second) and returns its URL.
    /// `ext` picks the container and codec: "flac" (FLAC) or "wav" (24-bit PCM, for the not-FLAC path).
    static func url(seconds: Double = 90, ext: String = "flac") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kima-clock-v2-\(Int(seconds)).\(ext)")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let settings: [String: Any] = [
            AVFormatIDKey: ext == "flac" ? kAudioFormatFLAC : kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let partial = url.deletingPathExtension().appendingPathExtension("partial.\(ext)")   // the extension picks the container
        try? FileManager.default.removeItem(at: partial)
        let file = try AVAudioFile(forWriting: partial, settings: settings, commonFormat: .pcmFormatInt32, interleaved: false)
        let total = Int(seconds * sampleRate), chunk = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk)),
              let channels = buffer.int32ChannelData else { throw CocoaError(.fileWriteUnknown) }
        var noise: UInt32 = 0x1234_5678
        var index = 0
        while index < total {
            let n = min(chunk, total - index)
            for k in 0..<n {
                let i = index + k
                channels[0][k] = Int32(i % (1 << 23)) << 8   // 24-bit value = sample index
                noise = noise &* 1_664_525 &+ 1_013_904_223
                let swell = 0.5 + 0.5 * sin(2 * Double.pi * Double(i) / sampleRate / 23)
                let amplitude = Int32(pow(2, 4 + 10 * swell))
                channels[1][k] = (Int32(bitPattern: noise >> 8) % amplitude) << 8
            }
            buffer.frameLength = AVAudioFrameCount(n)
            try file.write(from: buffer)
            index += n
        }
        try FileManager.default.moveItem(at: partial, to: url)
        return url
    }
}

// MARK: - Clock tap

/// Reads the left channel's sample index off the item while it plays (pre-effects, so volume 0
/// doesn't zero it). `heardSeconds` is the newest position decoded from the audio itself.
final class ClockTap {
    private let lock = NSLock()
    private var _latestIndex: Int?
    private var rate: Double = 0

    var heardSeconds: Double? {
        lock.withLock { _latestIndex.flatMap { rate > 0 ? Double($0) / rate : nil } }
    }

    func attach(to item: AVPlayerItem) async throws {
        guard let track = try await item.asset.loadTracks(withMediaType: .audio).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
            init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
            finalize: { tap in Unmanaged<ClockTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, _, asbd in
                let me = Unmanaged<ClockTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                me.lock.withLock { me.rate = asbd.pointee.mSampleRate }
            },
            unprepare: nil,
            process: { tap, frames, _, abl, framesOut, flagsOut in
                var range = CMTimeRange()
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, abl, flagsOut, &range, framesOut) == noErr else { return }
                let me = Unmanaged<ClockTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let list = UnsafeMutableAudioBufferListPointer(abl)
                guard framesOut.pointee > 0, let p = list[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                let v = Int((Double(p[0]) * Double(1 << 23)).rounded())
                me.lock.withLock { me._latestIndex = (v % (1 << 23) + (1 << 23)) % (1 << 23) }
            })
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap) == noErr,
              let tap else { throw CocoaError(.featureUnsupported) }
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
    }
}
