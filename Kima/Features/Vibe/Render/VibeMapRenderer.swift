import MetalKit
import simd
import UIKit

/// Everything the renderer needs from the screen that owns it.
struct VibeMapInput {
    var tracks: [VibeMapTrack]
    var mapKey: String
    /// Bumps when a different map arrives; the renderer rebuilds its buffers on a change.
    var mapGeneration: Int
    var highlightedIds: [String]
    var operationSourceId: String?
    var selectedId: String?
    var playingId: String?
    var queueIds: [String]
    var locateTrigger: Int
    var homeTrigger: Int
    /// Bumps to fly the camera to `flyToId` (a search pick).
    var flyTrigger: Int = 0
    var flyToId: String? = nil
    var reduceMotion: Bool
    /// Mood key of the pinned chip (`happy` or `moodHappy`); its stars take the mood colour. Nil: no tint.
    var focusMood: String? = nil
    /// What built the queue; colours the ring on its first star.
    var operationKind: VibeOperationKind = .songPath
    /// The song path's ends while its panel is open: ringed, and joined by a faint line once both are set.
    var pathStartId: String? = nil
    var pathEndId: String? = nil
}

/// Mirror of `Uniforms` in `VibeShaders.metal`. 304 bytes; field order and alignment must match.
struct VibeShaderUniforms {
    var viewProj: simd_float4x4        //   0
    var view: simd_float4x4            //  64
    var camRight: SIMD4<Float>         // 128
    var camUp: SIMD4<Float>            // 144
    var starlight: SIMD4<Float>        // 160
    /// Core share, core minimum px, edge softness px, halo reach.
    var starCore: SIMD4<Float>         // 176
    /// Halo steepness, halo strength, size scale, growth cap.
    var starHalo: SIMD4<Float>         // 192
    var viewSize: SIMD2<Float>         // 208
    var time: Float                    // 216
    var reveal: Float                  // 220
    var revealFade: Float              // 224
    var pxPerPt: Float                 // 228
    var homeDistance: Float            // 232
    var minPt: Float                   // 236
    var maxPt: Float                   // 240
    /// Index of the pinned mood in `VibeField.moodKeys`; -1 when none.
    var focusMood: Float = -1          // 244
    /// Chart: projection y scale, dot spacing pt, dot diameter pt, glint on/off.
    var projScaleY: Float = 0          // 248
    var spacingPt: Float = 0           // 252
    var dotPt: Float = 0               // 256
    var motion: Float = 1              // 260
    /// Dot spacing along a queue segment, world units.
    var chartStep: Float = 0           // 264
    var pad1: Float = 0                // 268
    var pad2: Float = 0                // 272
    var pad3: Float = 0                // 276
    var pad4: Float = 0                // 280
    var pad5: Float = 0                // 284
    /// Pinned mood colour (linear light) and how far the tint has eased in, 0 to 1.
    var focusColourMix: SIMD4<Float> = .zero   // 288
}

/// One record per star in the star buffer; mirrors `StarAttr` in `VibeShaders.metal` (48 bytes).
struct VibeStarAttr {
    var posSize: SIMD4<Float>
    var colourPhase: SIMD4<Float>
    /// Twinkle amplitude, reveal delay, dominant mood index (-1 none).
    var twinkleReveal: SIMD4<Float>
}

/// One drawn batch of chart dots, all in one colour.
struct VibeChartDraw {
    let buffer: MTLBuffer
    let count: Int
    /// Linear-light colour.
    let colour: SIMD3<Float>
}

/// Draws the 3-d vibe map with Metal: background, far stars, lines, stars, rings. Lives on the main thread
/// (the `MTKView` display link and the gesture recognisers both run there).
final class VibeMapRenderer: NSObject, MTKViewDelegate {
    struct Pipelines {
        let background: MTLRenderPipelineState
        let chart: MTLRenderPipelineState
        let sky: MTLRenderPipelineState
        let star: MTLRenderPipelineState
        let ring: MTLRenderPipelineState
    }

    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipelines: Pipelines
    weak var view: MTKView?

    // Inputs
    var input: VibeMapInput?
    var sceneStale = true
    var goalsDirty = true
    var linesDirty = true
    var pendingLocate = false
    var pendingHome = false
    var pendingFlyId: String?

    // Scene, built once the view has a size
    var field: VibeField?
    var camera: VibeOrbitCamera?
    var picker: VibeScreenPicker?
    var emphasis = VibeEmphasis(count: 0)
    var goals: [Float] = []
    var emphSettled = false
    var attrBuffer: MTLBuffer?
    var skyBuffer: MTLBuffer?
    var emphBuffers: [MTLBuffer] = []
    var emphIndex = 0
    var emphTrailing = 0
    var chartDraws: [VibeChartDraw] = []
    /// Dot spacing along a queue segment, world units; set with the chart (`baseSize * 0.15`).
    var chartStep: Float = 0
    var atHome = true
    /// How far the pinned-mood tint has eased in, 0 to 1.
    var focusMix: Float = 0
    /// The last pinned mood (index, linear colour), kept so the tint can ease out.
    var focusLast: (index: Float, colour: SIMD3<Float>)?

    // Clock
    let startTime = CACurrentMediaTime()
    var revealStart = CACurrentMediaTime()
    var lastFrame = CACurrentMediaTime()
    let inflight = DispatchSemaphore(value: 3)

    // DEBUG measurements and test hooks
    var frameCount = 0
    var drawSeconds = 0.0
    var statsWindowStart = CACurrentMediaTime()
    var onDebugStar: ((CGPoint?) -> Void)?
    var lastDebugPose: SIMD3<Float>?
    var firstFrameTime: CFTimeInterval?
    var debugLocateFired = false
    var debugZoomOutPending = VibeDebugFlags.zoomOut
    /// Bumps on every scene build or view-size change so a late zoom-out measurement can tell it is stale.
    var limitEpoch = 0

    init?(view: MTKView) {
        // Render pipeline states handed over by the launch pre-warm when it has finished,
        // built here otherwise. Nothing waits on the pre-warm: opening the map early keeps
        // exactly the old behaviour, paying the same cost it paid before.
        let prewarmed = VibeMapPrewarm.take()
        guard let device = view.device ?? VibeMapPrewarm.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        func make(_ name: String, _ v: String, _ f: String, _ blend: VibeMapPipeline.Blend) -> MTLRenderPipelineState? {
            if let hit = prewarmed?[name] { return hit }
            return VibeMapPipeline.make(device, library: library, vertex: v, fragment: f, blending: blend)
        }
        guard let bg = make("background", "bg_vertex", "bg_fragment", .opaque),
              let chart = make("chart", "chart_vertex", "chart_fragment", .normal),
              let sky = make("sky", "sky_vertex", "sky_fragment", .normal),
              let star = make("star", "star_vertex", "star_fragment", .normal),
              let ring = make("ring", "ring_vertex", "ring_fragment", .normal) else { return nil }
        self.device = device
        self.queue = queue
        self.pipelines = Pipelines(background: bg, chart: chart, sky: sky, star: star, ring: ring)
        self.view = view
        super.init()
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid
        view.framebufferOnly = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.delegate = self
    }

    // MARK: Input

    /// Take new inputs from SwiftUI and note what changed.
    func update(_ new: VibeMapInput) {
        let old = input
        input = new
        if old == nil || old?.mapGeneration != new.mapGeneration { sceneStale = true }
        if old?.highlightedIds != new.highlightedIds || old?.selectedId != new.selectedId
            || old?.playingId != new.playingId { goalsDirty = true }
        if old?.pathStartId != new.pathStartId || old?.pathEndId != new.pathEndId { linesDirty = true }
        if old?.focusMood != new.focusMood { requestFrame() }
        if let old, old.locateTrigger != new.locateTrigger { pendingLocate = true }
        if let old, old.homeTrigger != new.homeTrigger { pendingHome = true }
        if let old, old.flyTrigger != new.flyTrigger { pendingFlyId = new.flyToId }
        if old?.reduceMotion != new.reduceMotion { configureLoop() }
        requestFrame()
    }

    /// 60 fps normally; under Reduce Motion the view redraws only when something asks.
    func configureLoop() {
        guard let view, let input else { return }
        view.isPaused = input.reduceMotion
        view.enableSetNeedsDisplay = input.reduceMotion
    }

    func requestFrame() {
        if input?.reduceMotion == true { view?.setNeedsDisplay() }
    }

    // MARK: Scene

    /// Build the star data, camera and GPU buffers for the current map.
    func buildScene(size: SIMD2<Float>) {
        guard let input else { return }
        let f = VibeField(tracks: input.tracks)
        field = f
        var cam = VibeOrbitCamera(field: f, viewSize: size)
        atHome = !cam.restoreMemory(mapKey: input.mapKey)
        camera = cam
        picker = VibeScreenPicker(positions: f.positions)
        revealStart = CACurrentMediaTime()

        let moods = f.moods
        var attrs = [VibeStarAttr]()
        attrs.reserveCapacity(f.count)
        for i in 0..<f.count {
            attrs.append(VibeStarAttr(posSize: SIMD4(f.positions[i], f.sizes[i]),
                                      colourPhase: SIMD4(f.colours[i], f.phases[i]),
                                      twinkleReveal: SIMD4(f.twinkleAmps[i], f.reveals[i], moods[i], 0)))
        }
        attrBuffer = attrs.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: max(1, $0.count)) }
        let ones = [Float](repeating: 1, count: max(1, f.count))
        // Six slots. The CPU writes slot `emphIndex` at the top of the update, before this
        // frame's command buffer is gated, and up to three command buffers are in flight with
        // three drawables outstanding — with three slots the write landed on a slot a
        // submitted frame could still be reading.
        // "The CPU can write to uniforms at any time and the GPU can read from it … you can
        // trample over the values by overwriting them before the GPU is done reading them"
        // (Foundations of Game Engine Development, Vol. 3, quoted in docs/reviews/metal-audit.md).
        emphBuffers = (0..<6).compactMap { _ in
            ones.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }
        }
        emphasis = VibeEmphasis(count: f.count)
        goalsDirty = true
        emphTrailing = 3

        if skyBuffer == nil {
            let sky = VibeSky.buffer()
            skyBuffer = sky.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }
        }
        linesDirty = true
        lastDebugPose = nil
        logHome()
        measureZoomOutLimit()
    }

    /// Rebuild the song path's row of dots.
    func rebuildChart() {
        linesDirty = false
        guard let input, let f = field else { chartDraws = []; chartStep = 0; return }
        chartStep = f.baseSize * VibeMapStyle.chartStepFactor
        var out = [VibeChartDraw]()
        func add(_ dots: [VibeChartDot], _ colour: SIMD3<Float>) {
            guard !dots.isEmpty, let buf = dots.withUnsafeBytes({
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)
            }) else { return }
            out.append(VibeChartDraw(buffer: buf, count: dots.count, colour: colour))
        }
        let chord = VibeChart.buildPathChord(startId: input.pathStartId, endId: input.pathEndId,
                                             indexById: f.indexById, positions: f.positions,
                                             sizes: f.sizes, goals: goals, moods: f.moods,
                                             baseSize: f.baseSize)
        add(chord, VibeMapStyle.starlight)
        chartDraws = out
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { requestFrame() }
}
