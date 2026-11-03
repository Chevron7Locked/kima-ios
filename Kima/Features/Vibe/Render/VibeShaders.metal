#include <metal_stdlib>
using namespace metal;

// Shaders for the 3-d vibe map. Output is linear light, premultiplied, into a
// .bgra8Unorm_srgb target (the hardware encodes to sRGB on write).
// Draw order: background, far stars, lines, song stars, rings.
// The star core is sized in pixels so a small star's light barely changes with where its
// centre falls inside a pixel. Every star number comes from VibeMapStyle through the uniforms.

struct Uniforms {            // 304 bytes; Swift VibeShaderUniforms mirrors it field for field
    float4x4 viewProj;       //   0
    float4x4 view;           //  64
    float4 camRight;         // 128
    float4 camUp;            // 144
    float4 starlight;        // 160  rgb linear
    float4 starCore;         // 176  core share, core minimum px, edge softness px, halo reach
    float4 starHalo;         // 192  halo steepness, halo strength, size scale, growth cap
    float2 viewSize;         // 208  points
    float time;              // 216
    float reveal;            // 220
    float revealFade;        // 224
    float pxPerPt;           // 228
    float homeDistance;      // 232
    float minPt;             // 236  smallest star, points
    float maxPt;             // 240  largest star, points
    float focusMood;         // 244  pinned mood index, -1 none
    float projScaleY;        // 248  projection y scale, 1 / tan(fov / 2)
    float spacingPt;         // 252  chart dot spacing, points
    float dotPt;             // 256  chart dot diameter, points
    float motion;            // 260  1 while time runs, 0 in the still frames (glint stops)
    float chartStep;         // 264  dot spacing along a queue segment, world units
    float pad1;              // 268
    float pad2;              // 272
    float pad3;              // 276
    float pad4;              // 280
    float pad5;              // 284
    float4 focus;            // 288  pinned mood rgb linear, ease-in 0..1
};

static float3 srgbToLinear(float3 s) {
    return select(pow((s + 0.055) / 1.055, 2.4), s / 12.92, s <= 0.04045);
}

// Darkens the edges of the frame (postprocessing vignette, offset 0.22, darkness 0.82).
static float vignette(float2 pixel, constant Uniforms &u) {
    float2 uv = pixel / (u.viewSize * u.pxPerPt);
    float x = distance(uv, float2(0.5)) * (0.82 + 0.22);
    float t = clamp((x - 0.8) / (0.22 * 0.799 - 0.8), 0.0, 1.0);   // GLSL smoothstep(0.8, 0.1758, x)
    return t * t * (3.0 - 2.0 * t);
}

// MARK: Background

struct BgOut { float4 position [[position]]; };

vertex BgOut bg_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    BgOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

// The only glow: a very light violet ellipse behind everything.
fragment float4 bg_fragment(BgOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = in.position.xy / u.pxPerPt;
    float2 c = float2(u.viewSize.x * 0.50, u.viewSize.y * 0.30);
    float2 r = float2(u.viewSize.x * 1.20, u.viewSize.y * 0.95);
    float t = length((p - c) / r);
    const float3 s0 = float3(22.0, 11.0, 28.0) / 255.0;   // #160b1c
    const float3 s1 = float3(11.0, 5.0, 16.0) / 255.0;    // #0b0510
    const float3 s2 = float3(5.0, 2.0, 9.0) / 255.0;      // #050209
    const float3 s3 = float3(2.0, 1.0, 4.0) / 255.0;      // #020104
    float3 col;
    if (t < 0.22) col = mix(s0, s1, t / 0.22);
    else if (t < 0.44) col = mix(s1, s2, (t - 0.22) / 0.22);
    else if (t < 0.64) col = mix(s2, s3, (t - 0.44) / 0.20);
    else if (t < 1.0) col = mix(s3, float3(0.0), (t - 0.64) / 0.36);
    else col = float3(0.0);
    return float4(srgbToLinear(col), 1.0);
}

// MARK: Star shape (song stars and far stars)

static float4 starShade(float2 pc, float4 pos, float sizePx, float tw, float emph, float show,
                        float3 colour, constant Uniforms &u) {
    float r = length(pc - 0.5) * 2.0;                                      // 0 centre .. 1 sprite edge
    if (r > 1.0 || show <= 0.0) discard_fragment();
    float h = sizePx * 0.5;                                                // sprite radius, pixels
    float rp = r * h;                                                      // distance from centre, pixels
    float rc = max(u.starCore.x * h, u.starCore.y);                        // core radius, at least starCore.y px
    float aa = u.starCore.z;                                               // core edge half-width, pixels
    float core = 1.0 - smoothstep(rc - aa, rc + aa, rp);
    float halo = pow(max(0.0, 1.0 - rp / (u.starCore.w * h)), u.starHalo.x) * u.starHalo.y;
    float a = min(1.0, core * 0.95 + halo);
    float alpha = min(1.0, a * 0.9 * clamp(tw, 0.0, 3.0) * emph * show);   // star opacity 0.9
    float3 rgb = colour * vignette(pos.xy, u);
    return float4(rgb * alpha, alpha);
}

// MARK: Song stars

struct StarOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float sizePx;
    float3 colour;
    float tw;
    float emph;
    float show;
};

// One record per star, 48 bytes; Swift VibeStarAttr mirrors it.
struct StarAttr {
    float4 posSize;        // xyz position, w size
    float4 colourPhase;    // rgb linear colour, w phase
    float4 twinkleReveal;  // x twinkle amplitude, y reveal delay, z dominant mood index (-1 none)
};

vertex StarOut star_vertex(uint vid [[vertex_id]],
                           constant Uniforms &u [[buffer(0)]],
                           const device StarAttr *attrs [[buffer(1)]],
                           const device float *emphs [[buffer(2)]]) {
    StarAttr a = attrs[vid];
    float3 pos = a.posSize.xyz;
    float size = a.posSize.w;
    float phase = a.colourPhase.w;
    float twAmp = a.twinkleReveal.x, aReveal = a.twinkleReveal.y;
    float mood = a.twinkleReveal.z;
    float emph = emphs[vid];

    float4 viewPos = u.view * float4(pos, 1.0);
    float depth = max(-viewPos.z, 0.001);
    float grow = min(u.homeDistance / depth, u.starHalo.w);                 // never more than the cap times home size
    float glow = 1.0 + 0.6 * (emph - 1.0);
    float pt = size * u.starHalo.z * grow * glow;

    StarOut o;
    o.position = u.viewProj * float4(pos, 1.0);
    o.pointSize = clamp(pt, u.minPt, u.maxPt) * u.pxPerPt;
    o.sizePx = o.pointSize;

    float sp = 0.5 + fract(phase * 0.1591) * 1.3;
    o.tw = 1.0 - twAmp * (0.5 + 0.5 * sin(u.time * sp + phase));

    float3 c = a.colourPhase.xyz;
    float tint = u.focus.w * step(abs(mood - u.focusMood), 0.5) * step(-0.5, mood);
    if (tint > 0.0) {
        float lum = max(max(c.r, c.g), c.b);
        c = mix(c, u.focus.rgb * (0.55 + lum * 0.6), tint * 0.85);
    }
    // Emphasis goes toward white, except a pinned mood's stars keep their colour at highlight
    // strength (1.35); only the playing and selected stars above that whiten.
    float whiteFrom = 1.0 + 0.35 * tint;
    if (emph > whiteFrom) c = mix(c, u.starlight.rgb, min(1.0, (emph - whiteFrom) / 0.4));
    o.colour = c;
    o.show = clamp((u.reveal - aReveal) / u.revealFade, 0.0, 1.0);
    o.emph = emph;
    return o;
}

fragment float4 star_fragment(StarOut in [[stage_in]], float2 pc [[point_coord]],
                              constant Uniforms &u [[buffer(0)]]) {
    return starShade(pc, in.position, in.sizePx, in.tw, in.emph, in.show, in.colour, u);
}

// MARK: Far stars (directions only, drawn at infinity)

struct SkyOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float sizePx;
    float3 colour;
    float tw;
};

// attrs holds two float4 per star: [dir, twinkle amplitude] [rgb linear colour, phase]
vertex SkyOut sky_vertex(uint vid [[vertex_id]],
                         constant Uniforms &u [[buffer(0)]],
                         const device float4 *attrs [[buffer(1)]]) {
    float4 a0 = attrs[vid * 2], a1 = attrs[vid * 2 + 1];
    SkyOut o;
    o.colour = a1.xyz;
    o.tw = 1.0;
    o.pointSize = 1.0 * u.pxPerPt;
    o.sizePx = o.pointSize;
    float4 c = u.viewProj * float4(a0.xyz, 0.0);       // w = 0 drops the translation
    if (c.w <= 1e-4) {
        o.position = float4(2.0, 2.0, 2.0, 1.0);
        return o;
    }
    c.z = c.w * 0.999;
    o.position = c;
    float phase = a1.w;
    float sp = 0.2 + 0.4 * fract(phase * 0.1591);
    o.tw = 1.0 - a0.w * (0.5 + 0.5 * sin(u.time * sp + phase));
    return o;
}

fragment float4 sky_fragment(SkyOut in [[stage_in]], float2 pc [[point_coord]],
                             constant Uniforms &u [[buffer(0)]]) {
    return starShade(pc, in.position, in.sizePx, in.tw, 1.0, 1.0, in.colour, u);
}

// MARK: Chart dots (the queue's constellation stipple, port of the web's queueChart)
//
// Swift built the dots along the queue's segments (VibeChart.build). Here a dot is culled when zoomed
// out (level < need), when it sits inside the end star's disc plus clearance, and brightened in turn
// along the line by the glint. Dots are 1.5 pt round points; alpha carries the along-line fade.

struct ChartAttr {
    float4 posAlpha;               // xyz world position, w baked alpha
    float4 levelAlongSizeScale;    // lod level, glint order (2j), end star's size, end star's glow
    float4 endPosClear;            // xyz end star's position, w clear radius, points
    float4 moodPad;                // x end star's mood index (-1 none)
};

struct ChartOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 colourOpacity;
};

vertex ChartOut chart_vertex(uint vid [[vertex_id]],
                             constant Uniforms &u [[buffer(0)]],
                             const device ChartAttr *attrs [[buffer(1)]],
                             constant float4 &tint [[buffer(2)]]) {
    ChartAttr a = attrs[vid];
    ChartOut o;
    float4 c = u.viewProj * a.posAlpha;
    if (c.w <= 1e-4) {
        o.position = float4(2.0, 2.0, 2.0, 1.0);
        o.pointSize = 0.0;
        o.colourOpacity = float4(0.0);
        return o;
    }
    o.position = c;
    float depth = max(-(u.view * a.posAlpha).z, 0.001);
    // Points per world unit at the dot's depth (the projection's y scale maps NDC to half-screen).
    float pxPerUnit = u.projScaleY * 0.5 * u.viewSize.y / depth;
    float need = log2(max(u.spacingPt / max(u.chartStep * pxPerUnit, 1e-4), 1.0));

    // The end star's drawn size (points) at its own depth, as star_vertex sizes it.
    float4 endPos = float4(a.endPosClear.xyz, 1.0);
    float4 ec = u.viewProj * endPos;
    float eDepth = max(-(u.view * endPos).z, 0.001);
    float focus = step(abs(a.moodPad.x - u.focusMood), 0.5) * step(-0.5, a.moodPad.x) * u.focus.w;
    float grow = min(u.homeDistance / eDepth, u.starHalo.w);
    float endPt = clamp(a.levelAlongSizeScale.z * u.starHalo.z * grow * a.levelAlongSizeScale.w
                        * (1.0 + focus * 0.25), u.minPt, u.maxPt);
    float clearPt = endPt * 0.5 * u.starCore.x + a.endPosClear.w;   // dots stop short of the disc

    float apart = ec.w > 1e-4 ? length((c.xy / c.w - ec.xy / ec.w) * 0.5 * u.viewSize) : 1e6;
    float show = clamp(a.levelAlongSizeScale.x - need + 1.0, 0.0, 1.0)
                 * smoothstep(clearPt, clearPt + 2.0, apart);

    // The glint: a bright pass travelling along the line, one dot lit at a time.
    float along = a.levelAlongSizeScale.y;
    float glint = u.motion * step(0.0, along) * pow(max(0.0, sin(along * 0.16 - u.time * 0.9)), 18.0);

    o.pointSize = show > 0.0 ? u.dotPt * u.pxPerPt * (1.0 + glint * 0.6) : 0.0;
    float alpha = a.posAlpha.w * show * (1.0 + glint * 1.6);
    o.colourOpacity = float4(tint.rgb, alpha);
    return o;
}

fragment float4 chart_fragment(ChartOut in [[stage_in]], float2 pc [[point_coord]]) {
    float r = length(pc - 0.5) * 2.0;
    float a = in.colourOpacity.a * (1.0 - smoothstep(0.5, 1.0, r));
    if (a <= 0.0) discard_fragment();
    return float4(in.colourOpacity.rgb * a, a);
}

// MARK: Rings (radii in screen points, tracking the star's own disc: rings grow with zoom)

struct RingInst {
    float4 centreOuter;    // xyz world centre, w outer radius (points)
    float4 colourOpacity;  // rgb linear, a opacity
    float4 inner;          // x inner radius (points)
};

struct RingOut {
    float4 position [[position]];
    float2 local;          // points from the ring centre
    float4 colourOpacity;
    float outer;
    float inner;
};

vertex RingOut ring_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                           constant Uniforms &u [[buffer(0)]],
                           const device RingInst *inst [[buffer(1)]]) {
    RingInst r = inst[iid];
    RingOut o;
    o.colourOpacity = r.colourOpacity;
    o.outer = r.centreOuter.w;
    o.inner = r.inner.x;
    o.local = float2(0.0);
    float4 c = u.viewProj * float4(r.centreOuter.xyz, 1.0);
    if (c.w <= 1e-4) {
        o.position = float4(2.0, 2.0, 2.0, 1.0);
        return o;
    }
    float ext = r.centreOuter.w + 2.0;                                  // points, room for anti-aliasing
    float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
    c.xy += corner * ext / (0.5 * u.viewSize) * c.w;
    o.position = c;
    o.local = corner * ext;
    return o;
}

fragment float4 ring_fragment(RingOut in [[stage_in]]) {
    float d = length(in.local);
    float aa = max(fwidth(d), 1e-4);
    float inner = min(in.inner, in.outer - 1.5 * aa);
    float cov = smoothstep(inner - aa, inner + aa, d) * (1.0 - smoothstep(in.outer - aa, in.outer + aa, d));
    float alpha = in.colourOpacity.a * cov;
    return float4(in.colourOpacity.rgb * alpha, alpha);
}
