import MetalKit
import simd
import UIKit

extension VibeMapRenderer {

    /// The playing track's id: the real one, or (DEBUG) the one `-kima-vibe-fake-playing` names.
    var effectivePlayingId: String? {
        if let i = VibeDebugFlags.fakePlayingIndex, let f = field, f.trackIds.indices.contains(i) { return f.trackIds[i] }
        return input?.playingId
    }

    /// One frame: move the camera and the star brightness, then encode and present.
    func draw(in view: MTKView) {
        let t0 = CACurrentMediaTime()
        guard let input else { return }
        let size = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        guard size.x > 0, size.y > 0 else { return }
        if sceneStale || field == nil {
            sceneStale = false
            buildScene(size: size)
        }
        guard camera != nil, let f = field, let attrBuffer else { return }
        let reduce = input.reduceMotion
        let still = VibeDebugFlags.still
        let calm = reduce || still
        let dt = Float(min(0.1, t0 - lastFrame))
        lastFrame = t0
        if firstFrameTime == nil { firstFrameTime = t0 }

        if camera!.updateViewSize(size) {
            measureZoomOutLimit()
            if atHome { camera!.setPose(position: camera!.homePosition, target: camera!.fieldCentre) }
        }
        if pendingHome {
            pendingHome = false
            camera!.flyHome(reduceMotion: calm)
            atHome = true
        }
        if VibeDebugFlags.locate, !debugLocateFired, let t = firstFrameTime, t0 - t >= 0.5 {
            debugLocateFired = true
            pendingLocate = true
        }
        if pendingLocate {
            pendingLocate = false
            if let id = effectivePlayingId, let i = f.indexById[id] {
                camera!.fly(toStarAt: f.positions[i], reduceMotion: calm)
                atHome = false
            }
        }
        if let id = pendingFlyId {
            pendingFlyId = nil
            if let i = f.indexById[id] {
                camera!.fly(toStarAt: f.positions[i], reduceMotion: calm)
                atHome = false
            }
        }
        if VibeDebugFlags.orbitDemo { camera!.theta += 0.2 * dt }
        camera!.frame(dt: dt)
        if let z = VibeDebugFlags.zoomFactor { camera!.setZoom(z) }
        camera!.tickMemory(mapKey: input.mapKey)

        if goalsDirty {
            goalsDirty = false
            goals = VibeEmphasis.goals(count: f.count, indexById: f.indexById,
                                       highlighted: Set(input.highlightedIds),
                                       selected: input.selectedId, playing: effectivePlayingId)
            emphSettled = false
        }
        if !emphSettled {
            emphSettled = emphasis.ease(toward: goals, dt: dt, reduceMotion: reduce)
            emphTrailing = 3
        }
        if emphTrailing > 0, !emphBuffers.isEmpty {
            emphIndex = (emphIndex + 1) % emphBuffers.count
            let values = emphasis.values
            values.withUnsafeBytes { emphBuffers[emphIndex].contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            emphTrailing -= 1
        }
        if linesDirty { rebuildChart() }

        var u = uniforms(view: view, reduce: calm, now: t0)
        applyFocus(to: &u, dt: dt, calm: calm)
        let cam = camera!
        var rings = VibeRings.build(indexById: f.indexById, positions: f.positions, sizes: f.sizes,
                                    emph: emphasis.values,
                                    view: cam.viewMatrix, viewProj: cam.viewProjection,
                                    viewSize: CGSize(width: CGFloat(cam.viewSize.x), height: CGFloat(cam.viewSize.y)),
                                    home: cam.homeDistance,
                                    operationSourceId: input.operationSourceId ?? (VibeDebugFlags.operation == nil ? nil : effectivePlayingId),
                                    playingId: effectivePlayingId, selectedId: input.selectedId,
                                    operationKind: VibeDebugFlags.operation ?? input.operationKind,
                                    pathStartId: input.pathStartId, pathEndId: input.pathEndId,
                                    queueIds: input.queueIds)
        let breath = VibeRings.breathOpacity(time: u.time, reduceMotion: calm)
        for i in rings.indices where rings[i].breathes { rings[i].opacity = breath }

        presentFrame(view: view, uniforms: &u, attrBuffer: attrBuffer, rings: rings, count: f.count)

        if reduce, needsMoreFrames { view.setNeedsDisplay() }
        #if DEBUG
        reportStats(t0: t0)
        #endif
    }

    /// The pinned mood's palette key, from the screen or (DEBUG) the launch argument; nil when none or unknown.
    var focusKey: String? {
        guard let raw = input?.focusMood ?? VibeDebugFlags.focusMood else { return nil }
        let key = VibeMoodPalette.paletteKey(forAxis: raw)
        return VibeField.moodKeys.contains(key) ? key : nil
    }

    /// 1 while a mood is pinned, else 0.
    var focusGoal: Float { focusKey == nil ? 0 : 1 }

    /// Ease the pinned-mood tint in and out (rate 8 per second, as on the web) and hand it to the shader.
    func applyFocus(to u: inout VibeShaderUniforms, dt: Float, calm: Bool) {
        let goal = focusGoal
        if calm || abs(goal - focusMix) < 0.002 {
            focusMix = goal
        } else {
            focusMix += (goal - focusMix) * min(1, dt * 8)
        }
        if let key = focusKey, let idx = VibeField.moodKeys.firstIndex(of: key),
           let colour = VibeMoodPalette.linearColour(for: key) {
            focusLast = (Float(idx), colour)
        }
        guard let last = focusLast, focusMix > 0 else { return }
        u.focusMood = last.index
        u.focusColourMix = SIMD4(last.colour, focusMix)
    }

    /// True while something is still moving, so on-demand drawing keeps going.
    var needsMoreFrames: Bool {
        guard let cam = camera else { return false }
        let moving = cam.isFlying || abs(cam.pendingTheta) > 1e-4 || abs(cam.pendingPhi) > 1e-4
            || simd_length(cam.pendingPan) > 1e-4
        return moving || !emphSettled || emphTrailing > 0 || sceneStale || focusMix != focusGoal
    }

    /// `calm` is Reduce Motion or the DEBUG still hook: time stands at 0 and the reveal is finished.
    func uniforms(view: MTKView, reduce calm: Bool, now: CFTimeInterval) -> VibeShaderUniforms {
        let cam = camera!
        return VibeShaderUniforms(
            viewProj: cam.viewProjection, view: cam.viewMatrix,
            camRight: SIMD4(cam.right, 0), camUp: SIMD4(cam.up, 0),
            starlight: SIMD4(VibeMapStyle.starlight, 1),
            starCore: SIMD4(VibeMapStyle.coreShare, VibeMapStyle.coreMinPx, VibeMapStyle.edgePx, VibeMapStyle.haloReach),
            starHalo: SIMD4(VibeMapStyle.haloPower, VibeMapStyle.haloStrength,
                            VibeMapStyle.starSizeK, VibeMapStyle.starGrowthCap),
            viewSize: cam.viewSize,
            time: calm ? 0 : Float(now - startTime),
            reveal: calm ? 1e6 : Float(now - revealStart),
            revealFade: VibeField.revealFade,
            pxPerPt: Float(view.contentScaleFactor),
            homeDistance: cam.homeDistance,
            minPt: VibeMapStyle.starMinPt,
            maxPt: VibeMapStyle.starMaxPt,
            projScaleY: cam.projectionMatrix.columns.1.y,
            spacingPt: VibeMapStyle.chartSpacingPt,
            dotPt: VibeMapStyle.chartDotPt,
            motion: calm ? 0 : 1,
            chartStep: chartStep)
    }

    /// Encode background, far stars, lines, stars, rings in that order and present.
    func presentFrame(view: MTKView, uniforms u: inout VibeShaderUniforms, attrBuffer: MTLBuffer,
                      rings: [VibeRing], count: Int) {
        // Take the in-flight slot first, then the drawable: a drawable held while the frame
        // waits on a free command buffer is a window-server resource parked for nothing, and
        // the frame's own CPU work wants to happen before the drawable is acquired.
        inflight.wait()
        guard let drawable = view.currentDrawable, let rpd = view.currentRenderPassDescriptor else {
            inflight.signal()
            return
        }
        guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else {
            inflight.signal()
            return
        }
        let sem = inflight
        cmd.addCompletedHandler { _ in sem.signal() }
        let ustride = MemoryLayout<VibeShaderUniforms>.stride

        enc.setVertexBytes(&u, length: ustride, index: 0)
        enc.setFragmentBytes(&u, length: ustride, index: 0)

        let sky = VibeDebugFlags.layerOn("sky"), stars = VibeDebugFlags.layerOn("stars")
        if sky {
            enc.setRenderPipelineState(pipelines.background)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            if let skyBuffer {
                enc.setRenderPipelineState(pipelines.sky)
                enc.setVertexBuffer(skyBuffer, offset: 0, index: 1)
                enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: VibeMapStyle.farStarCount)
            }
        }

        if stars {
            if !chartDraws.isEmpty, VibeDebugFlags.layerOn("lines") {
                enc.setRenderPipelineState(pipelines.chart)
                for d in chartDraws {
                    var tint = SIMD4<Float>(d.colour, 1)
                    enc.setVertexBuffer(d.buffer, offset: 0, index: 1)
                    enc.setVertexBytes(&tint, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
                    enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: d.count)
                }
            }

            if count > 0, !emphBuffers.isEmpty {
                enc.setRenderPipelineState(pipelines.star)
                enc.setVertexBuffer(attrBuffer, offset: 0, index: 1)
                enc.setVertexBuffer(emphBuffers[emphIndex], offset: 0, index: 2)
                enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
            }
        }

        if !rings.isEmpty, VibeDebugFlags.layerOn("rings") {
            var inst = [SIMD4<Float>]()
            for r in rings {
                inst.append(SIMD4(r.centre, r.outerRadius))
                inst.append(SIMD4(r.colour, r.opacity))
                inst.append(SIMD4(r.innerRadius, 0, 0, 0))
            }
            enc.setRenderPipelineState(pipelines.ring)
            inst.withUnsafeBytes { enc.setVertexBytes($0.baseAddress!, length: $0.count, index: 1) }
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: rings.count)
        }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
