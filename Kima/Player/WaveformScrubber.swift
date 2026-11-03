import SwiftUI

// MARK: - WaveformScrubber

/// Waveform-shaped seek scrubber. PLAYED = one solid accent gradient rect; DOWNLOAD fill = lighter
/// accent when `downloadProgress` is set; REMAINING = peak-height bars (flat rail if `peaks` is
/// empty). Playhead is hidden and the gesture masked out when `!canSeek`. A time tooltip floats
/// while dragging. The highPriorityGesture beats FullPlayerView's dismiss-swipe so scrubs are never hijacked.
struct WaveformScrubber: View {

    let duration: Double
    let displayTime: Double
    let isScrubbing: Bool
    let onScrubChanged: (Double) -> Void   // progress 0…1 while dragging
    let onScrubEnded: (Double) -> Void     // progress 0…1 on release → seek
    var peaks: [Double] = []               // normalised 0–1; empty → flat-line fallback
    var canSeek: Bool = true               // false while loading/error → disable + mute
    var downloadProgress: Double? = nil    // 0–1 secondary lighter fill (nil = streaming)
    /// Adaptive accent primary color — pass `env.accent.color` from the parent view.
    /// Canvas closures cannot read @Environment directly, so the parent threads it in.
    var accent: Color = KimaColor.brand
    /// Adaptive accent deep variant — pass `env.accent.deep` from the parent view.
    var accentDeep: Color = KimaColor.brandDeep

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let progress   = duration > 0 ? max(0, min(1, displayTime / duration)) : 0.0
            let playheadX  = progress * w

            ZStack(alignment: .topLeading) {
                waveformCanvas(w: w, h: h, progress: progress)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let p = max(0, min(1, value.location.x / w))
                                onScrubChanged(p)
                            }
                            .onEnded { value in
                                let p = max(0, min(1, value.location.x / w))
                                onScrubEnded(p)
                            },
                        including: canSeek ? .all : .none
                    )

                // Scrub time-preview tooltip
                if isScrubbing && canSeek && duration > 0 {
                    Text(displayTime.durationFormatted)
                        .font(KimaType.meta.monospacedDigit())
                        .foregroundStyle(KimaColor.textPrimary)
                        .padding(.horizontal, KimaSpacing.sm)
                        .padding(.vertical, KimaSpacing.xs)
                        .background(Color.black.opacity(0.80), in: Capsule())
                        .offset(
                            x: max(0, min(w - 56, playheadX - 24)),
                            y: -(h * 0.5 + 20)
                        )
                }
            }
        }
        .frame(height: 48)
    }

    // MARK: - Canvas

    @ViewBuilder
    private func waveformCanvas(
        w: CGFloat, h: CGFloat, progress: Double
    ) -> some View {
        // Pre-compute all captures; every captured value must be Sendable.
        let localPeaks    = peaks
        let localW        = w
        let localH        = h
        let localProg     = progress
        let localScrub    = isScrubbing
        let localCanSeek  = canSeek
        let localDlProg   = downloadProgress

        let cBrand     = accent
        let cBrandDeep = accentDeep
        let cMuted     = KimaColor.textMuted
        let cRail      = KimaColor.surfaceRaised

        Canvas { ctx, _ in
            let midY      = localH / 2
            let phX       = localProg * localW

            // ── 1. Background rail (fallback only) ──────────────────────────────
            if localPeaks.isEmpty {
                var rail = Path()
                rail.addRoundedRect(
                    in: CGRect(x: 0, y: midY - 1.5, width: localW, height: 3),
                    cornerSize: CGSize(width: 1.5, height: 1.5)
                )
                ctx.fill(rail, with: .color(cRail.opacity(0.65)))
            }

            // ── 1.5. Download progress fill (lighter amber, under played region) ─
            if let dp = localDlProg, dp > 0 {
                let dpX = min(localW, dp * localW)
                var dpFill = Path()
                dpFill.addRoundedRect(
                    in: CGRect(x: 0, y: midY - 1.5, width: dpX, height: 3),
                    cornerSize: CGSize(width: 1.5, height: 1.5)
                )
                ctx.fill(dpFill, with: .color(cBrand.opacity(0.18)))
            }

            // ── 2. Played region ─────────────────────────────────────────────────
            if phX > 1 {
                let fillW = max(2, phX)
                var played = Path()
                played.addRoundedRect(
                    in: CGRect(x: 0, y: midY - 1.5, width: fillW, height: 3),
                    cornerSize: CGSize(width: 1.5, height: 1.5)
                )
                if localCanSeek {
                    // Active: amber gradient
                    ctx.fill(played, with: .linearGradient(
                        Gradient(colors: [cBrandDeep, cBrand]),
                        startPoint: CGPoint(x: 0,     y: midY),
                        endPoint:   CGPoint(x: fillW, y: midY)
                    ))
                } else {
                    // Disabled: muted grey
                    ctx.fill(played, with: .color(cMuted.opacity(0.30)))
                }
            }

            // ── 3. Remaining waveform bars ───────────────────────────────────────
            if !localPeaks.isEmpty {
                let count   = localPeaks.count
                let slotW   = localW / CGFloat(count)
                let barW    = max(1.0, slotW - 2.0)
                let maxBarH = localH * 0.82
                let minBarH: CGFloat = 3

                for i in 0..<count {
                    let barCenterX = CGFloat(i) * slotW + slotW * 0.5
                    guard barCenterX >= phX else { continue }

                    let amp    = localPeaks[i]
                    let barH   = max(minBarH, CGFloat(amp) * maxBarH)
                    let corner = min(barW * 0.5, 2.0)

                    var bar = Path()
                    bar.addRoundedRect(
                        in: CGRect(
                            x:      CGFloat(i) * slotW + (slotW - barW) * 0.5,
                            y:      midY - barH * 0.5,
                            width:  barW,
                            height: barH
                        ),
                        cornerSize: CGSize(width: corner, height: corner)
                    )
                    ctx.fill(bar, with: .color(cMuted.opacity(0.48)))
                }
            }

            // ── 4. Playhead: amber rule + centre dot (only when seekable) ────────
            guard localCanSeek && phX > 0 && phX < localW else { return }

            let phH: CGFloat = localScrub ? 40 : 32
            let phW: CGFloat = localScrub ? 2.5 : 2.0

            var rule = Path()
            rule.addRoundedRect(
                in: CGRect(
                    x:      phX - phW * 0.5,
                    y:      midY - phH * 0.5,
                    width:  phW,
                    height: phH
                ),
                cornerSize: CGSize(width: phW * 0.5, height: phW * 0.5)
            )
            ctx.fill(rule, with: .color(cBrand))

            let dotR: CGFloat = localScrub ? 5.0 : 4.0
            var dot = Path()
            dot.addEllipse(in: CGRect(
                x: phX - dotR, y: midY - dotR,
                width: dotR * 2, height: dotR * 2
            ))
            ctx.fill(dot, with: .color(cBrand))
        }
    }
}
