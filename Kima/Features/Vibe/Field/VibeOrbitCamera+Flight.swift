import Foundation
import simd

/// An eased camera move from one pose to another.
struct VibeCameraFlight {
    var fromPosition: SIMD3<Float>
    var fromTarget: SIMD3<Float>
    var toPosition: SIMD3<Float>
    var toTarget: SIMD3<Float>
    var duration: Float
    var elapsed: Float = 0
}

extension VibeOrbitCamera {
    typealias Flight = VibeCameraFlight

    /// Fast start, long gentle stop.
    static func easeOutExpo(_ t: Float) -> Float { t >= 1 ? 1 : 1 - pow(2, -10 * t) }

    var isFlying: Bool { flight != nil }

    mutating func startFlight(toPosition: SIMD3<Float>, toTarget: SIMD3<Float>, duration: Float, reduceMotion: Bool) {
        flight = Flight(fromPosition: position, fromTarget: target, toPosition: toPosition, toTarget: toTarget,
                        duration: reduceMotion ? 0.001 : duration)
    }

    /// Fly back to the whole-library view (1.2 s).
    mutating func flyHome(reduceMotion: Bool) {
        startFlight(toPosition: homePosition, toTarget: fieldCentre, duration: 1.2, reduceMotion: reduceMotion)
    }

    /// Fly to a star (1.1 s), landing no further out than 0.28 of the home distance from it, on the side the camera is already on.
    mutating func fly(toStarAt star: SIMD3<Float>, reduceMotion: Bool) {
        let away = simd_normalize(position - target)
        let landing = star + away * min(distance, homeDistance * VibeMapStyle.locateFactor)
        startFlight(toPosition: landing, toTarget: star, duration: 1.1, reduceMotion: reduceMotion)
    }

    mutating func advanceFlight(dt: Float) {
        guard var f = flight else { return }
        f.elapsed += dt
        let t = min(1, f.elapsed / f.duration)
        let e = Self.easeOutExpo(t)
        setPose(position: f.fromPosition + (f.toPosition - f.fromPosition) * e,
                target: f.fromTarget + (f.toTarget - f.fromTarget) * e)
        flight = t >= 1 ? nil : f
    }

    /// Call once per frame after `frame`. Every 15 frames: refresh the overview flag and, when
    /// not flying and the camera has moved, remember the pose for the next visit to this map.
    mutating func tickMemory(mapKey: String) {
        frameCounter += 1
        guard frameCounter % 15 == 0 else { return }
        isOverview = simd_length(position - target) > homeDistance * VibeMapStyle.overviewFactor
        guard flight == nil else { return }
        let p = position
        if let last = lastSavedPosition, simd_length_squared(p - last) <= 0.01 { return }
        lastSavedPosition = p
        VibeCameraMemory.save(position: p, target: target, mapKey: mapKey)
    }

    /// Put the camera where it was last left on this same map. Returns false (and changes nothing) otherwise.
    @discardableResult
    mutating func restoreMemory(mapKey: String) -> Bool {
        guard let pose = VibeCameraMemory.pose(for: mapKey) else { return false }
        setPose(position: pose.position, target: pose.target)
        lastSavedPosition = pose.position
        return true
    }
}

/// The last camera pose of this session, kept only for the same map (same `mapKey`).
enum VibeCameraMemory {
    struct Pose { let position: SIMD3<Float>; let target: SIMD3<Float>; let mapKey: String }
    private static let lock = NSLock()
    private nonisolated(unsafe) static var stored: Pose?

    static func save(position: SIMD3<Float>, target: SIMD3<Float>, mapKey: String) {
        lock.lock(); defer { lock.unlock() }
        stored = Pose(position: position, target: target, mapKey: mapKey)
    }

    static func pose(for mapKey: String) -> Pose? {
        lock.lock(); defer { lock.unlock() }
        guard let s = stored, s.mapKey == mapKey else { return nil }
        return s
    }

    /// Forget the stored pose (tests reset the static memory between cases).
    static func clear() {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
