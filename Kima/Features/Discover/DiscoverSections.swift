import SwiftUI

// MARK: - DiscoverHeroSection
//
// Title and stats pill (week date, track count, duration).
// Bricolage display face, amber "weekly" accent.

struct DiscoverHeroSection: View {
    let playlist: DiscoverPlaylist?


    private var totalDuration: Double {
        playlist?.tracks.reduce(0) { $0 + $1.duration } ?? 0
    }

    private var weekLabel: String {
        guard let ws = playlist?.weekStart else { return "" }
        guard let date = Formatters.iso8601FullDate.date(from: String(ws.prefix(10))) else { return ws }
        return Formatters.displayDate(date)
    }

    private var durationLabel: String {
        let h = Int(totalDuration) / 3600
        let m = (Int(totalDuration) % 3600) / 60
        return h > 0 ? "~\(h) hr \(m) min" : "\(m) min"
    }

    /// Distinct artist count — real, derived from the tracks themselves (not a placeholder).
    private var artistCount: Int {
        Set((playlist?.tracks ?? []).map(\.artist)).count
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: KimaSpacing.md) {
                // Title
                KimaScreenTitle(title: "discover weekly")

                // Curatorial voice — "the weekly dig" framing, not a generic algorithm blurb.
                Text("new albums picked from what you play. refreshed weekly.")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)

                // Stats byline — only when playlist is loaded
                if let p = playlist {
                    HStack(spacing: KimaSpacing.md) {
                        KimaKicker(title: weekLabel)
                        KimaKicker(title: "\(p.totalCount) \(p.totalCount == 1 ? "track" : "tracks")")
                        if artistCount > 0 {
                            KimaKicker(title: "\(artistCount) \(artistCount == 1 ? "artist" : "artists")", dotColor: KimaColor.hairline)
                        }
                        if totalDuration > 0 {
                            KimaKicker(title: durationLabel, dotColor: KimaColor.hairline)
                        }
                    }

                    // Subtle "may be stale" indicator — shown only when the server flags it.
                    if p.stale == true {
                        HStack(spacing: KimaSpacing.xs) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 9, weight: .semibold))
                            Text("may be out of date")
                                .font(KimaType.meta)
                                .tracking(0.1)
                        }
                        .foregroundStyle(KimaColor.textMuted)
                        .padding(.horizontal, KimaSpacing.sm)
                        .padding(.vertical, KimaSpacing.xs)
                        .background(KimaColor.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.top, KimaSpacing.xl)
            .padding(.bottom, KimaSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - DiscoverActionBar
//
// Play/Pause (amber fill) + Cancel (destructive outline).

struct DiscoverActionBar: View {
    let playlist: DiscoverPlaylist?
    let isPlaylistPlaying: Bool
    let isPlaying: Bool
    let isGenerating: Bool
    let onPlayToggle: () -> Void
    let onCancelGeneration: () -> Void

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            // Play / Pause — shown only when playlist has tracks
            if let p = playlist, !p.tracks.isEmpty {
                let playing = isPlaylistPlaying && isPlaying
                KimaPrimaryButton(title: playing ? "playing" : "play all",
                                  systemImage: playing ? "pause.fill" : "play.fill",
                                  size: .compact, action: onPlayToggle)
                    .disabled(isGenerating)
            }

            // Cancel generation
            if isGenerating {
                Button(action: onCancelGeneration) {
                    HStack(spacing: KimaSpacing.xs) {
                        Image(systemName: "xmark")
                        Text("cancel")
                            .font(KimaType.meta)
                    }
                    .foregroundStyle(KimaColor.danger.opacity(0.8))
                    .padding(.horizontal, KimaSpacing.lg)
                    .frame(height: 44)
                    .background(KimaColor.danger.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(KimaColor.danger.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.xs)
        .padding(.bottom, KimaSpacing.sm)
    }
}

// MARK: - DiscoverHowItWorks
//
// Static explainer card.

struct DiscoverHowItWorks: View {
    private let bullets: [String] = [
        "finds artists similar to the ones you play (using Last.fm)",
        "sorts them by match: high, medium, explore, wild card",
        "picking a song downloads its whole album to /music/discovery on your server",
        "like an album to keep it. unliked albums are removed at week's end",
        "albums won't repeat for 6 months",
        "albums that can't be downloaded are replaced. you can still preview them from Deezer",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            Text("how it works")
                .font(KimaType.section)
                .foregroundStyle(KimaColor.textPrimary)

            VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                ForEach(bullets.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: KimaSpacing.sm) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(KimaColor.textFaint)
                            .frame(width: 14)
                            .padding(.top, 2)  // optical: sits the icon on the first text line
                        Text(bullets[i])
                            .font(KimaType.body)
                            .foregroundStyle(KimaColor.textSecondary)
                    }
                }
            }
        }
        .padding(KimaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))
        .overlay(RoundedRectangle(cornerRadius: KimaRadius.card).strokeBorder(KimaColor.hairline, lineWidth: 1))
        .padding(.horizontal, KimaSpacing.lg)
    }
}

// MARK: - DiscoverUnavailableSection
//
// Collapsible section with a retry-all button.

struct DiscoverUnavailableSection: View {
    let unavailable: [UnavailableAlbum]
    let isRetrying: Bool
    /// Nil when this listener may not start downloads: the retry is hidden.
    let onRetryAll: (() -> Void)?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: KimaSpacing.sm) {
                        Image(systemName: "music.note")
                            .foregroundStyle(KimaColor.caution)
                        Text("\(unavailable.count) album\(unavailable.count == 1 ? "" : "s") unavailable")
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textSecondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(KimaColor.textMuted)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                if let onRetryAll {
                    Button(action: onRetryAll) {
                        HStack(spacing: KimaSpacing.xs) {
                            if isRetrying {
                                ProgressView().scaleEffect(0.7).tint(KimaColor.caution)
                            } else {
                                Image(systemName: "arrow.clockwise").font(.system(size: 11))
                            }
                            Text("retry all").font(KimaType.meta)
                        }
                        .foregroundStyle(KimaColor.caution)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRetrying)
                }
            }
            .padding(KimaSpacing.lg)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(unavailable) { album in
                        UnavailableAlbumRow(album: album)
                        KimaHairline()
                    }
                }
            }
        }
        .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))
        .overlay(RoundedRectangle(cornerRadius: KimaRadius.card).strokeBorder(KimaColor.hairline, lineWidth: 1))
        .padding(.horizontal, KimaSpacing.lg)
    }
}

private struct UnavailableAlbumRow: View {
    let album: UnavailableAlbum

    private var attemptLabel: String {
        (album.attemptNumber ?? 0) == 0 ? "original" : "replacement #\(album.attemptNumber!)"
    }

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            // Placeholder cover (no image URL on unavailable)
            RoundedRectangle(cornerRadius: KimaRadius.image)
                .fill(KimaColor.surfaceRaised)
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "music.note").foregroundStyle(KimaColor.textMuted))

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(album.album.lowercased())
                    .font(KimaType.headline)
                    .foregroundStyle(KimaColor.textPrimary)
                    .lineLimit(1)
                Text(album.artist.lowercased())
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(attemptLabel)
                .font(KimaType.meta)
                .foregroundStyle((album.attemptNumber ?? 0) == 0 ? KimaColor.caution : KimaColor.textMuted)
                .padding(.horizontal, KimaSpacing.sm)
                .padding(.vertical, KimaSpacing.xs)
                .background(
                    (album.attemptNumber ?? 0) == 0 ? KimaColor.caution.opacity(0.12) : KimaColor.fillQuiet,
                    in: Capsule()
                )
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm)
    }
}
