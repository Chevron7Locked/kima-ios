import SwiftUI

// MARK: Mood (key wheel: circle of fifths, brightness = plays, tap selects, button plays)

struct StatsMood: View {
    private typealias Math = StatsKeyWheelMath

    let s: Signature
    /// Shelf.analysis.done — the "from audio analysis of N tracks" figure (web parity).
    let analysed: Int
    let period: StatsPeriod

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @State private var selected: Math.Wedge?
    @State private var busy = false

    var body: some View {
        if let key = s.key {
            let c = Math.counts(key.all.map { ($0.key, $0.scale, $0.plays) })
            let maxPlays = Swift.max(1, (c.major + c.minor).max() ?? 1)
            let total = key.all.map(\.plays).reduce(0, +)
            VStack(alignment: .leading, spacing: KimaSpacing.md) {
                StatsFinding(
                    claim: key.top.first.map { "top key: \($0.key.lowercased())" } ?? "keys",
                    note: "from audio analysis of \(analysed.formatted(.number)) tracks · tap a key to play it")
                wheel(key, counts: c, maxPlays: maxPlays, total: total)
                    .frame(maxWidth: .infinity, alignment: .center)
                captionRow(counts: c, total: total)
            }
        }
    }

    // MARK: wheel

    private func wheel(_ key: KeyStats, counts c: (major: [Int], minor: [Int]), maxPlays: Int, total: Int) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let ctr = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Canvas { ctx, _ in
                    for i in 0..<12 {
                        for ring in [Math.Ring.major, .minor] {
                            let plays = ring == .major ? c.major[i] : c.minor[i]
                            let inner = (ring == .major ? Math.majorInner : Math.minorInner) * radius
                            let outer = (ring == .major ? Math.majorOuter : Math.minorOuter) * radius
                            let a0 = Angle.degrees(Math.centreDegrees(i) - Math.halfSpanDegrees)
                            let a1 = Angle.degrees(Math.centreDegrees(i) + Math.halfSpanDegrees)
                            var p = Path()
                            p.addArc(center: ctr, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
                            p.addArc(center: ctr, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
                            p.closeSubpath()
                            ctx.fill(p, with: .color(plays > 0
                                ? KimaColor.brand.opacity(Math.fillOpacity(plays, max: maxPlays))
                                : Color.white.opacity(0.04)))
                            if selected == Math.Wedge(index: i, ring: ring) {
                                ctx.stroke(p, with: .color(Color.white), lineWidth: 1.5)
                            }
                            let loud = Math.isLoud(plays, max: maxPlays)
                            ctx.draw(
                                Text(Math.label(index: i, ring: ring))
                                    .font(KimaType.fitted(radius * (ring == .major ? 0.088 : 0.068)))
                                    .foregroundStyle(loud ? Color(hex: 0x0A0A0A) : KimaColor.textPrimary.opacity(0.75)),
                                at: Math.labelPoint(index: i, ring: ring, center: ctr, radius: radius),
                                anchor: .center)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    let w = Math.hitTest(v.location, center: ctr, radius: radius)
                    selected = (w == nil || w == selected) ? nil : w
                })
                .sensoryFeedback(.selection, trigger: selected)
                .accessibilityElement()
                .accessibilityLabel(wheelLabel(key))
                .accessibilityValue(caption(counts: c, total: total))
                .accessibilityIdentifier("key-wheel")
                .accessibilityAdjustableAction { dir in
                    adjust(dir, counts: c)
                }

                VStack(spacing: 0) {
                    Text("\(Int(key.minorPct.rounded()))%")
                        .font(KimaType.fitted(radius * 0.19, bricolage: true))
                        .foregroundStyle(KimaColor.textPrimary)
                        .monospacedDigit()
                    Text("minor")
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textMuted)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 320)
    }

    private func wheelLabel(_ key: KeyStats) -> String {
        let pct = "\(Int(key.minorPct.rounded()))% minor"
        guard let top = key.top.first?.key.lowercased() else { return "key wheel · \(pct)" }
        return "key wheel · top key: \(top) · \(pct)"
    }

    // MARK: caption

    private func plays(of w: Math.Wedge, _ c: (major: [Int], minor: [Int])) -> Int {
        w.ring == .major ? c.major[w.index] : c.minor[w.index]
    }

    private func playsText(_ n: Int) -> String { n == 1 ? "1 play" : "\(n.formatted(.number)) plays" }

    private func caption(counts c: (major: [Int], minor: [Int]), total: Int) -> String {
        guard let w = selected else {
            return "outer: major · inner: minor · \(playsText(total))"
        }
        let name = Math.displayName(index: w.index, ring: w.ring)
        let n = plays(of: w, c)
        return n > 0 ? "\(name): \(playsText(n))" : "\(name): no plays"
    }

    private func captionRow(counts c: (major: [Int], minor: [Int]), total: Int) -> some View {
        HStack(spacing: KimaSpacing.md) {
            Text(caption(counts: c, total: total))
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
                .monospacedDigit()
                .accessibilityIdentifier("key-wheel-caption")
            Spacer(minLength: 0)
            if let w = selected, plays(of: w, c) > 0 { playButton(w) }
        }
        .frame(minHeight: 44)
    }

    private func playButton(_ w: Math.Wedge) -> some View {
        Button { play() } label: {
            HStack(spacing: KimaSpacing.sm) {
                if busy { ProgressView().controlSize(.small) } else { Image(systemName: "play.fill") }
                Text("play \(Math.displayName(index: w.index, ring: w.ring))")
            }
            .font(KimaType.headline)
            .foregroundStyle(KimaColor.textPrimary)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("key-wheel-play")
    }

    /// A failed request shows nothing (web parity); the selection stays.
    private func play() {
        busy = true
        Task {
            defer { busy = false }
            guard let w = selected,
                  let tracks = try? await env.client.getPlayableSlice(
                      of: "key", key: Math.apiKey(index: w.index, ring: w.ring), limit: 40, period: period),
                  !tracks.isEmpty else { return }
            player.play(tracks: tracks)
        }
    }

    // MARK: VoiceOver

    /// Wedges with plays: most plays first, then major before minor, then index.
    private func order(_ c: (major: [Int], minor: [Int])) -> [Math.Wedge] {
        var all: [(w: Math.Wedge, n: Int)] = []
        for i in 0..<12 {
            if c.major[i] > 0 { all.append((Math.Wedge(index: i, ring: .major), c.major[i])) }
            if c.minor[i] > 0 { all.append((Math.Wedge(index: i, ring: .minor), c.minor[i])) }
        }
        return all.sorted {
            if $0.n != $1.n { return $0.n > $1.n }
            if $0.w.ring != $1.w.ring { return $0.w.ring == .major }
            return $0.w.index < $1.w.index
        }.map(\.w)
    }

    private func adjust(_ dir: AccessibilityAdjustmentDirection, counts c: (major: [Int], minor: [Int])) {
        let list = order(c)
        guard !list.isEmpty else { return }
        let at = selected.flatMap { list.firstIndex(of: $0) }
        switch dir {
        case .increment:
            if let at { selected = list[Swift.min(at + 1, list.count - 1)] } else { selected = list[0] }
        case .decrement:
            if let at, at > 0 { selected = list[at - 1] } else { selected = nil }
        @unknown default: break
        }
    }
}
