import MetalKit
import simd
import UIKit

extension VibeMapRenderer {

    // MARK: Gestures (points)

    /// A touch took over from any flight in progress.
    func beginGesture() {
        camera?.flight = nil
        atHome = false
    }

    /// The finger lifted (or the gesture was cancelled).
    func endGesture() {
        requestFrame()
    }

    func orbit(dx: CGFloat, dy: CGFloat) {
        camera?.orbit(dx: Float(dx), dy: Float(dy))
        requestFrame()
    }

    func pan(dx: CGFloat, dy: CGFloat) {
        camera?.pan(dx: Float(dx), dy: Float(dy))
        requestFrame()
    }

    func pinch(ratio: CGFloat, at point: CGPoint) {
        camera?.pinch(ratio: Float(ratio), at: SIMD2(Float(point.x), Float(point.y)))
        requestFrame()
    }

    /// Id of the star under a touch at `point`, or nil for empty space.
    func trackId(at point: CGPoint) -> String? {
        guard let cam = camera, let picker, let f = field else { return nil }
        let i = picker.pick(viewProjection: cam.viewProjection, width: cam.viewSize.x, height: cam.viewSize.y,
                            x: Float(point.x), y: Float(point.y))
        return i.map { f.trackIds[$0] }
    }

    // MARK: DEBUG hooks

    /// How far out the camera may go before the map reads as a blob (see `VibeOrbitCamera.zoomOutLimit`).
    /// Measured off the main thread; until it arrives the framing distance is both home and maximum.
    func measureZoomOutLimit() {
        guard let cam = camera else { return }
        limitEpoch += 1
        let epoch = limitEpoch
        let positions = cam.positions, target = cam.fieldCentre, back = cam.homeBack
        let framing = cam.framingDistance, size = cam.viewSize
        let n = VibeMapStyle.separationPoints(pxPerPt: Float(view?.contentScaleFactor ?? 3))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let limit = VibeOrbitCamera.zoomOutLimit(positions: positions, target: target, back: back,
                                                     framing: framing, viewSize: size, n: n)
            DispatchQueue.main.async { self?.applyZoomOutLimit(limit, epoch: epoch, n: n) }
        }
    }

    private func applyZoomOutLimit(_ limit: Float, epoch: Int, n: Float) {
        guard epoch == limitEpoch, var cam = camera else { return }
        cam.applyZoomOutLimit(limit)
        if atHome { cam.setPose(position: cam.homePosition, target: cam.fieldCentre) }
        camera = cam
        logHome()
        if debugZoomOutPending {
            debugZoomOutPending = false
            camera!.setPose(position: cam.fieldCentre + cam.homeBack * cam.maxDistance, target: cam.fieldCentre)
            atHome = false
            #if DEBUG
            let s = VibeOrbitCamera.closeStats(positions: cam.positions, target: cam.fieldCentre, back: cam.homeBack,
                                               d: cam.maxDistance, viewSize: cam.viewSize, n: n)
            NSLog("vibe-map limit max=%.2f home=%.2f framing=%.2f closeShare=%.3f onscreen=%d",
                  cam.maxDistance, cam.homeDistance, cam.framingDistance, s.share, s.onScreen)
            #endif
        }
        requestFrame()
    }

    /// Log how many stars are on screen at the home pose.
    func logHome() {
        #if DEBUG
        guard let cam = camera, let f = field else { return }
        let vp = VibeOrbitCamera.projectionMatrix(aspect: cam.aspect)
            * VibeOrbitCamera.viewMatrix(position: cam.homePosition, target: cam.fieldCentre)
        var on = 0
        for p in f.positions {
            let c = vp * SIMD4(p, 1)
            if c.w > 0, abs(c.x / c.w) <= 1, abs(c.y / c.w) <= 1 { on += 1 }
        }
        NSLog("vibe-map home n=%d onscreen=%d distance=%.2f", f.count, on, cam.homeDistance)
        #endif
    }

    #if DEBUG
    /// Average CPU time inside `draw(in:)` over 300 frames, plus the wall-clock frame rate.
    func reportStats(t0: CFTimeInterval) {
        let now = CACurrentMediaTime()
        drawSeconds += now - t0
        frameCount += 1
        if frameCount % 15 == 0 { publishDebugStar() }
        guard frameCount >= 300 else { return }
        let wall = now - statsWindowStart
        NSLog("vibe-map draw avg=%.3fms over %d frames, %.1f fps",
              drawSeconds / Double(frameCount) * 1000, frameCount, Double(frameCount) / max(wall, 1e-6))
        frameCount = 0
        drawSeconds = 0
        statsWindowStart = now
    }

    /// Tell the test hook where the on-screen star nearest the view centre is.
    func publishDebugStar() {
        guard let cb = onDebugStar, let cam = camera, let picker, let f = field else { return }
        let pos = cam.position + cam.target * 1.7
        if lastDebugPose == pos { return }
        lastDebugPose = pos
        let vp = cam.viewProjection, w = cam.viewSize.x, h = cam.viewSize.y
        var best: CGPoint?
        var bestD = CGFloat.infinity
        for i in 0..<f.count {
            let p = picker.screenOf(i, viewProjection: vp, width: w, height: h)
            guard !p.x.isNaN, p.x > 20, p.y > 20, p.x < CGFloat(w) - 20, p.y < CGFloat(h) - 20 else { continue }
            let d = hypot(p.x - CGFloat(w) / 2, p.y - CGFloat(h) / 2)
            if d < bestD { bestD = d; best = p }
        }
        cb(best)
    }
    #endif
}
