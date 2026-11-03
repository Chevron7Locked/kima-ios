import Metal
import os.log

private let prewarmLog = Logger(subsystem: "com.chevron7locked.kima", category: "vibe-prewarm")

/// The map's five render pipeline states, built off the main thread when the signed-in shell
/// appears — and one device lookup shared by the layer, the renderer and this pre-warm.
///
/// Building a pipeline state costs real processing time, and Apple's guidance is to pay it at
/// launch, not in the frame path: *"Creating a pipeline state takes valuable processing time, so
/// all of the above should be a [one-time cost] … allocate at launch"* (Delivering Optimized
/// Metal Apps and Games, WWDC19 606; quoted in docs/reviews/metal-audit.md). Before this, the
/// five states were created inside the renderer's init, i.e. on the main thread at the moment
/// the map opens (observed once at 82 ms cold on an M3 Ultra, 1.3-1.5 ms warm — see the audit).
///
/// The renderer takes these when they are ready and builds its own when they are not, so
/// opening the map before the pre-warm finishes behaves exactly as before: nothing waits here.
enum VibeMapPrewarm {
    /// Shared so the view, the renderer and the pre-warm describe the same hardware.
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()

    private static let lock = NSLock()
    nonisolated(unsafe) private static var states: [String: MTLRenderPipelineState]?
    nonisolated(unsafe) private static var started = false

    /// Fire-and-forget: safe to call more than once, does no work after the first call,
    /// never blocks the caller.
    static func start() {
        lock.lock()
        if started { lock.unlock(); return }
        started = true
        lock.unlock()
        guard let device, let library = device.makeDefaultLibrary() else {
            prewarmLog.log("no Metal device or default library; pre-warm skipped")
            return
        }
        Task.detached(priority: .utility) {
            var built = [String: MTLRenderPipelineState]()
            for entry in VibeMapPipeline.all {
                if let state = VibeMapPipeline.make(device, library: library, vertex: entry.vertex,
                                                    fragment: entry.fragment, blending: entry.blending) {
                    built[entry.name] = state
                }
            }
            // Only hand over a complete set: a partial set would make the renderer's guard
            // succeed with a nil state it then has to build mid-frame.
            lock.lock()
            if built.count == VibeMapPipeline.all.count { states = built }
            lock.unlock()
            prewarmLog.log("pre-warm built \(built.count, privacy: .public)/\(VibeMapPipeline.all.count, privacy: .public)")
        }
    }

    /// The finished states, nil while the pre-warm is running or if it failed.
    static func take() -> [String: MTLRenderPipelineState]? {
        lock.lock()
        defer { lock.unlock() }
        return states
    }
}
