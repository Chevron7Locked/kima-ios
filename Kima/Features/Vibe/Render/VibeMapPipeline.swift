import Metal

/// One of the map's render pipelines, built through a single shared path so the launch-time
/// pre-warm ([VibeMapPrewarm]()) and the renderer's own fallback can never describe different
/// blending.
enum VibeMapPipeline {
    enum Blend { case opaque, normal }

    /// The five states the map draws with, in the order the renderer binds them.
    static let all: [(name: String, vertex: String, fragment: String, blending: Blend)] = [
        ("background", "bg_vertex", "bg_fragment", .opaque),
        ("chart", "chart_vertex", "chart_fragment", .normal),
        ("sky", "sky_vertex", "sky_fragment", .normal),
        ("star", "star_vertex", "star_fragment", .normal),
        ("ring", "ring_vertex", "ring_fragment", .normal),
    ]

    static func make(_ device: MTLDevice, library: MTLLibrary, vertex: String, fragment: String,
                     blending: Blend) -> MTLRenderPipelineState? {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: vertex)
        d.fragmentFunction = library.makeFunction(name: fragment)
        guard let a = d.colorAttachments[0] else { return nil }
        a.pixelFormat = .bgra8Unorm_srgb
        switch blending {
        case .opaque:
            a.isBlendingEnabled = false
        case .normal:
            a.isBlendingEnabled = true
            a.sourceRGBBlendFactor = .one
            a.destinationRGBBlendFactor = .oneMinusSourceAlpha
            a.sourceAlphaBlendFactor = .one
            a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try? device.makeRenderPipelineState(descriptor: d)
    }
}
