import Foundation
import simd

/// The map's camera: a port of the web's three.js `OrbitControls` as the vibe map configures it.
/// It orbits a target point; position = target + distance * (sin(phi) sin(theta), cos(phi), sin(phi) cos(theta)).
/// Pure maths, driven once per frame by `frame(dt:...)`.
struct VibeOrbitCamera {
    static let fovDegrees: Float = 50
    static let near: Float = 0.1
    static let far: Float = 1200
    static let damping: Float = 0.08
    static let rotateSpeed: Float = 0.55
    static let zoomSpeed: Float = 0.9
    static let polarEpsilon: Float = 1e-6
    var target: SIMD3<Float>
    var distance: Float
    var theta: Float
    var phi: Float
    /// View size in points.
    var viewSize: SIMD2<Float>
    var aspect: Float { viewSize.y > 0 ? viewSize.x / viewSize.y : 1 }

    let positions: [SIMD3<Float>]
    let fieldCentre: SIMD3<Float>
    let fieldRadius: Float
    /// The distance that frames the library (before the zoom-out limit is known).
    private(set) var framingDistance: Float
    /// Camera distance at home: the framing distance, pulled in if the zoom-out limit is nearer.
    private(set) var homeDistance: Float
    /// Farthest the camera may sit: the zoom-out limit ("never a blob"). Until it is measured, the framing distance.
    private(set) var maxDistance: Float
    /// Unit direction from the target to the home camera.
    private(set) var homeBack: SIMD3<Float>
    /// Polar angle limits; a flat map keeps to `VibeMapStyle.flatPolarRange`.
    private(set) var phiRange: ClosedRange<Float>
    var minDistance: Float { homeDistance * VibeMapStyle.minDistanceFactor }

    // Motion still to be applied, spread over the next frames.
    var pendingTheta: Float = 0
    var pendingPhi: Float = 0
    var pendingPan = SIMD3<Float>(repeating: 0)

    var flight: Flight?
    var frameCounter = 0
    var lastSavedPosition: SIMD3<Float>?
    /// True when the camera is farther out than `overviewFactor` of the home distance.
    var isOverview = true

    init(field: VibeField, viewSize: SIMD2<Float>) {
        self.positions = field.positions
        self.fieldCentre = field.centre
        self.fieldRadius = field.radius
        self.viewSize = viewSize
        self.target = field.centre
        self.distance = 1
        self.theta = 0
        self.phi = 1
        let pose = Self.homePose(positions: positions, aspect: viewSize.y > 0 ? viewSize.x / viewSize.y : 1)
        self.framingDistance = pose.distance
        self.homeDistance = pose.distance
        self.maxDistance = pose.distance
        self.homeBack = pose.back
        self.phiRange = Self.polarRange(positions: positions, centre: pose.target)
        setPose(position: homePosition, target: fieldCentre)
    }

    var homePosition: SIMD3<Float> { fieldCentre + homeBack * homeDistance }

    /// Call when the view's size changes: re-derives the home pose. Returns true if it changed.
    /// The zoom-out limit is stale after this; the caller measures it again.
    @discardableResult
    mutating func updateViewSize(_ size: SIMD2<Float>) -> Bool {
        guard size != viewSize else { return false }
        viewSize = size
        let pose = Self.homePose(positions: positions, aspect: aspect)
        framingDistance = pose.distance
        homeDistance = pose.distance
        maxDistance = pose.distance
        homeBack = pose.back
        return true
    }

    /// Take the measured zoom-out limit: home may not sit beyond it, and neither may the camera.
    mutating func applyZoomOutLimit(_ limit: Float) {
        maxDistance = max(limit, 1)
        homeDistance = min(framingDistance, maxDistance)
    }

    // MARK: Pose

    var position: SIMD3<Float> {
        target + distance * SIMD3(sin(phi) * sin(theta), cos(phi), sin(phi) * cos(theta))
    }

    var forward: SIMD3<Float> { simd_normalize(target - position) }
    var right: SIMD3<Float> { Self.rightAxis(forward: forward) }
    var up: SIMD3<Float> { simd_cross(right, forward) }

    /// Set the camera from a position and target, re-deriving distance and angles.
    mutating func setPose(position: SIMD3<Float>, target: SIMD3<Float>) {
        let offset = position - target
        let r = max(simd_length(offset), 1e-6)
        self.target = target
        self.distance = r
        self.phi = min(.pi - Self.polarEpsilon, max(Self.polarEpsilon, acos(max(-1, min(1, offset.y / r)))))
        self.theta = atan2(offset.x, offset.z)
    }

    /// Put the camera at `factor` times the home distance, within the zoom limits (DEBUG screenshots).
    mutating func setZoom(_ factor: Float) {
        distance = min(max(homeDistance * factor, minDistance), maxDistance)
    }

    // MARK: Matrices (right-handed, Metal clip z in 0...1)

    var viewMatrix: simd_float4x4 { Self.viewMatrix(position: position, target: target) }

    var projectionMatrix: simd_float4x4 { Self.projectionMatrix(aspect: aspect) }

    /// The camera's right axis; looking straight up or down has no defined right, so it falls back to +x.
    static func rightAxis(forward f: SIMD3<Float>) -> SIMD3<Float> {
        let r = simd_cross(f, SIMD3<Float>(0, 1, 0))
        return simd_length(r) < 1e-6 ? SIMD3<Float>(1, 0, 0) : simd_normalize(r)
    }

    static func viewMatrix(position p: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(target - p)
        let r = rightAxis(forward: f)
        let u = simd_cross(r, f)
        return simd_float4x4(columns: (
            SIMD4(r.x, u.x, -f.x, 0), SIMD4(r.y, u.y, -f.y, 0), SIMD4(r.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(r, p), -simd_dot(u, p), simd_dot(f, p), 1)))
    }

    static func projectionMatrix(aspect: Float) -> simd_float4x4 {
        let ys = 1 / tan(fovDegrees * .pi / 180 / 2)
        let xs = ys / aspect
        let zs = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4(xs, 0, 0, 0), SIMD4(0, ys, 0, 0), SIMD4(0, 0, zs, -1), SIMD4(0, 0, zs * near, 0)))
    }

    var viewProjection: simd_float4x4 { projectionMatrix * viewMatrix }

    // MARK: Gestures

    /// One-finger drag of (dx, dy) points. The motion is applied gradually by `frame`.
    mutating func orbit(dx: Float, dy: Float) {
        guard viewSize.y > 0 else { return }
        pendingTheta -= 2 * .pi * dx * Self.rotateSpeed / viewSize.y
        pendingPhi -= 2 * .pi * dy * Self.rotateSpeed / viewSize.y
    }

    /// Two-finger drag of (dx, dy) points: slides the scene with the fingers.
    mutating func pan(dx: Float, dy: Float) {
        guard viewSize.y > 0 else { return }
        let td = simd_length(position - target) * tan(Self.fovDegrees * .pi / 180 / 2)
        pendingPan += -right * (2 * dx * td / viewSize.y) + up * (2 * dy * td / viewSize.y)
    }

    /// Pinch by `ratio` (new spread / old spread) about `centroid` (view points). Zooms toward that point.
    mutating func pinch(ratio: Float, at centroid: SIMD2<Float>) {
        guard ratio > 0, viewSize.x > 0, viewSize.y > 0 else { return }
        let newDistance = min(maxDistance, max(minDistance, distance / pow(ratio, Self.zoomSpeed)))
        let ndcX = centroid.x / viewSize.x * 2 - 1
        let ndcY = 1 - centroid.y / viewSize.y * 2
        let tanHalf = tan(Self.fovDegrees * .pi / 180 / 2)
        let f = forward
        let dir = simd_normalize(f + right * (ndcX * tanHalf * aspect) + up * (ndcY * tanHalf))
        let newPosition = position + dir * (distance - newDistance)
        setPose(position: newPosition, target: newPosition + f * newDistance)
    }

    // MARK: Per-frame

    /// Move the camera one 60 Hz step: flight, or gesture damping; then keep it inside its limits.
    mutating func frame(dt: Float) {
        if flight != nil {
            advanceFlight(dt: dt)
            pendingTheta = 0; pendingPhi = 0; pendingPan = .zero
        } else {
            let k = Self.damping
            theta += pendingTheta * k
            phi = min(phiRange.upperBound, max(phiRange.lowerBound, phi + pendingPhi * k))
            target += pendingPan * k
            let keep = 1 - k
            pendingTheta *= keep; pendingPhi *= keep; pendingPan *= keep
        }
        applyLimits()
    }

    /// Keep the distance in range and the target within 1.3 radii of the field centre.
    mutating func applyLimits() {
        phi = min(phiRange.upperBound, max(phiRange.lowerBound, phi))
        distance = min(maxDistance, max(minDistance, distance))
        let off = target - fieldCentre
        let len = simd_length(off)
        let limit = fieldRadius * 1.3
        if len > limit {
            let shift = off * (limit / len) - off
            target += shift
        }
    }
}
