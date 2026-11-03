import MetalKit
import SwiftUI

/// The `MTKView` that shows the map, with its touch gestures:
/// one finger orbits, two fingers pan, pinch zooms, a tap picks, a double tap plays, a long press opens the menu.
struct VibeMetalLayer: UIViewRepresentable {
    @Environment(\.scenePhase) private var scenePhase
    let input: VibeMapInput
    /// Filled with the on-screen positions of the mood labels and the tracked stars.
    let projection: VibeProjection
    /// Stars the overlay marks (the selected one).
    let trackedIds: [String]
    var onTap: (String?) -> Void
    var onDoubleTap: (String) -> Void
    var onLongPress: (String) -> Void
    var onDebugStar: ((CGPoint?) -> Void)?
    /// Called once when the Metal renderer can't start (no device, library or pipeline).
    var onRendererFailed: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        // The same device the pre-warm built its pipeline states for; MTKView(device:) does not
        // replace a view's device afterwards, so this is the only reliable place to align them.
        let view = MTKView(frame: .zero, device: VibeMapPrewarm.device ?? MTLCreateSystemDefaultDevice())
        view.isAccessibilityElement = true
        view.accessibilityTraits = .image
        context.coordinator.projection = projection
        context.coordinator.attach(to: view)
        if context.coordinator.renderer == nil {
            let failed = onRendererFailed
            DispatchQueue.main.async { failed() }   // not during the view update
        }
        return view
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) { coordinator.stopProjection() }

    func updateUIView(_ view: MTKView, context: Context) {
        let c = context.coordinator
        c.onTap = onTap
        c.onDoubleTap = onDoubleTap
        c.onLongPress = onLongPress
        c.renderer?.onDebugStar = onDebugStar
        view.accessibilityLabel = "music map, \(input.tracks.count) tracks"
        // An invisible map at 60 fps is GPU and CPU work for pixels nobody can see: the
        // display link and the view both stop when the scene is not front-most. The frame
        // clock is CACurrentMediaTime and dt is clamped to 0.1 s in the frame builder, so the
        // first frame after a pause behaves like any other frame.
        let paused = scenePhase != .active
        view.isPaused = paused
        c.setPaused(paused)
        c.renderer?.update(input)
        c.setProjectionInputs(tracks: input.tracks, generation: input.mapGeneration, tracked: trackedIds)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var renderer: VibeMapRenderer?
        var onTap: (String?) -> Void = { _ in }
        var onDoubleTap: (String) -> Void = { _ in }
        var onLongPress: (String) -> Void = { _ in }
        var projection: VibeProjection?
        private var link: CADisplayLink?
        private var anchorsGeneration: Int?
        private var pinch: UIPinchGestureRecognizer?
        private var twoFingerPan: UIPanGestureRecognizer?

        /// Stops the projection tick along with the view; the two must not drift apart.
        func setPaused(_ paused: Bool) { link?.isPaused = paused }

        func attach(to view: MTKView) {
            renderer = VibeDebugFlags.metalFail ? nil : VibeMapRenderer(view: view)
            let link = CADisplayLink(target: self, selector: #selector(projectionTick))
            link.add(to: .main, forMode: .common)
            self.link = link

            let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
            orbit.minimumNumberOfTouches = 1
            orbit.maximumNumberOfTouches = 1
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let double = UITapGestureRecognizer(target: self, action: #selector(handleDouble(_:)))
            double.numberOfTapsRequired = 2
            let single = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            single.require(toFail: double)
            let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLong(_:)))
            long.minimumPressDuration = 0.45

            self.pinch = pinch
            self.twoFingerPan = pan
            for g in [orbit, pan, pinch, double, single, long] as [UIGestureRecognizer] {
                g.delegate = self
                view.addGestureRecognizer(g)
            }
        }

        func setProjectionInputs(tracks: [VibeMapTrack], generation: Int, tracked: [String]) {
            if anchorsGeneration != generation {
                anchorsGeneration = generation
                projection?.setAnchors(for: tracks)
            }
            projection?.setTracked(tracked)
        }

        func stopProjection() {
            link?.invalidate()
            link = nil
        }

        /// Every display frame: hand the camera to the projection, which ignores frames where nothing moved.
        @objc private func projectionTick() {
            guard let projection, let r = renderer, let cam = r.camera, let f = r.field else { return }
            projection.tick(viewProjection: cam.viewProjection,
                            viewSize: CGSize(width: CGFloat(cam.viewSize.x), height: CGFloat(cam.viewSize.y)),
                            overview: cam.isOverview) { id in f.indexById[id].map { f.positions[$0] } }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (g === pinch && other === twoFingerPan) || (g === twoFingerPan && other === pinch)
        }

        /// Tells the renderer when a finger goes down or lifts; true only while the gesture is changing.
        private func track(_ g: UIGestureRecognizer) -> Bool {
            switch g.state {
            case .began: renderer?.beginGesture()
            case .ended, .cancelled, .failed: renderer?.endGesture()
            default: break
            }
            return g.state == .changed
        }

        @objc private func handleOrbit(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            guard track(g) else { return }
            let t = g.translation(in: view)
            g.setTranslation(.zero, in: view)
            renderer?.orbit(dx: t.x, dy: t.y)
        }

        @objc private func handlePan(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            guard track(g) else { return }
            let t = g.translation(in: view)
            g.setTranslation(.zero, in: view)
            renderer?.pan(dx: t.x, dy: t.y)
        }

        @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let view = g.view else { return }
            guard track(g) else { return }
            let ratio = g.scale
            g.scale = 1
            renderer?.pinch(ratio: ratio, at: g.location(in: view))
        }

        @objc private func handleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let view = g.view else { return }
            onTap(renderer?.trackId(at: g.location(in: view)))
        }

        @objc private func handleDouble(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let view = g.view,
                  let id = renderer?.trackId(at: g.location(in: view)) else { return }
            onDoubleTap(id)
        }

        @objc private func handleLong(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let view = g.view,
                  let id = renderer?.trackId(at: g.location(in: view)) else { return }
            onLongPress(id)
        }
    }
}
