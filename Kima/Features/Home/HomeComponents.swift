import SwiftUI

// MARK: - HomeHeroView

/// Greeting masthead ("good evening" + library totals). Wordmark and date live in HomeGlassHeader.
struct HomeHeroView: View {
    let artistTotal: Int?
    let albumTotal:  Int?

    @Environment(AppEnvironment.self) private var env

    /// The on-device "dispatch" line, loaded once when Home appears. When present it REPLACES
    /// the stats subline; when nil (iOS <26, Apple Intelligence off, or generation failed) the
    /// stats subline shows exactly as before — never blank, never a spinner.
    @State private var dispatch: String?
    /// Slow breathe on the dispatch's accent "signal" dot — the on-air / live-signal cue.
    @State private var dispatchBreathe = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "good morning"
        case 12..<17: return "good afternoon"
        default:       return "good evening"
        }
    }

    private var subline: String {
        var parts: [String] = []
        if let a = artistTotal { parts.append("\(a) artist\(a == 1 ? "" : "s")") }
        if let al = albumTotal  { parts.append("\(al) album\(al == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    /// Top mood keys across the loaded vibe map (e.g. "moodElectronic"), matched by `HypeDeck.pick(for:)`.
    /// Empty until the map loads, then the pick falls back to the general deck. `topMoods` is computed once per
    /// load, not by re-grouping the (10k-20k track) array on every `body` evaluation.
    private var moodSignal: [String] {
        // The palette keys (moodHappy, …) that HypeDeck and the label table key on. The map sends
        // these; a bare axis name (happy, sad, …) is mapped to its key.
        env.vibeMapViewModel.topMoods.map { VibeMoodPalette.paletteKey(forAxis: $0) }
    }

    /// The same top moods as human words ("electronic", "chill") for the AI warp's prompt — the
    /// deck matches on keys, but the model reads words.
    private var moodWords: [String] {
        moodSignal.compactMap { VibeMoodPalette.labels[$0]?.lowercased() }
    }

    var body: some View {
        ZStack {
                VStack(alignment: .leading, spacing: KimaSpacing.md) {
                    let words = greeting.components(separatedBy: " ").filter { !$0.isEmpty }
                    let lastWord = (words.last ?? "").lowercased()
                    let leadingPart = (words.dropLast().map { $0.lowercased() }.joined(separator: " ")) + (words.count > 1 ? " " : "")

                    if words.isEmpty {
                        Text("")
                    } else {
                        // One Text with attributed runs: a concatenated `Text(…) + Text(…)` ignores
                        // minimumScaleFactor, and at 58pt "good evening" overflowed and clipped both edges.
                        // One ink color; amber is a mark, not a wash.
                        {
                            var attr = AttributedString(leadingPart + lastWord)
                            attr.foregroundColor = KimaColor.textPrimary
                            return Text(attr)
                        }()
                            .font(KimaType.hero)
                            .tracking(-0.4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .fixedSize(horizontal: false, vertical: true)
                            // No bell reservation: the greeting starts below the floating chrome row
                            // (top padding below), so it can use the full column width.
                    }
                Group {
                    if let dispatch {
                        // The station's voice: a small italic "dispatch" led by a breathing accent
                        // signal dot (on-air cue). Not the plain stats line.
                        HStack(alignment: .top, spacing: KimaSpacing.sm) {
                            Circle()
                                .fill(KimaColor.brand)
                                .frame(width: 5, height: 5)
                                .opacity(dispatchBreathe ? 0.9 : 0.4)
                                .padding(.top, 5)  // optical: centres the dot on the first text line
                            Text(dispatch)
                                .font(KimaType.body)
                                .italic()
                                .foregroundStyle(KimaColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .transition(.opacity)
                    } else {
                        if !subline.isEmpty {
                            Text(subline)
                                .font(KimaType.body)
                                .foregroundStyle(KimaColor.textMuted)
                                .lineLimit(1)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: dispatch)
                .onAppear {
                    guard !dispatchBreathe else { return }
                    withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                        dispatchBreathe = true
                    }
                }
            }
            .padding(.horizontal, KimaSpacing.lg)
            // Clears the floating chrome row (8pt inset + 44pt pill), then a full gutter so the greeting reads as its own group.
            .padding(.top, KimaLayout.topChromeHeight + KimaSpacing.lg)
            // The first section header's own top space (xxl) is the gap to the feed.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .task {
            // Opportunistically load the vibe map so the dispatch has a real mood signal to pick and
            // warp against. Idempotent/cached; the player's constellation backdrop needs it too.
            if case .loading = env.vibeMapViewModel.phase {
                await env.vibeMapViewModel.load(client: env.client)
            }
        }
        .task(id: moodSignal) {
            // Show the quote only once it is final, so the user never watches it being composed. Display is today's
            // cached line (instant), else the stats subline. One deck draw plus one Apple Intelligence warp per day
            // runs in the background and only writes the cache; the quote lands on the next open.
            if let cached = HypeDeck.cachedLineIfToday() { dispatch = cached; return }
            guard !moodSignal.isEmpty, !HypeDeck.todayLineResolved else { return }

            let line = HypeDeck.lineOfDay(for: moodSignal)   // persists the day's draw
            if dispatch == nil { dispatch = line }           // brand-new day: show the line
            // exactly as drawn (static, no swap) while the warp resolves behind it
            env.intelligence.refreshStatus()
            if let warped = await env.intelligence.warp(line: line, mood: moodWords),
               !warped.isEmpty,
               !KimaIntelligence.isClichedHype(warped),
               warped.count <= 140 {
                HypeDeck.recordWarp(warped)        // the AI result becomes today's final text
            } else {
                HypeDeck.recordWarpSkipped()       // model off/failed → curated draw stays final
            }
        }
    }
}

// MARK: - ContinueCard

/// "Continue Listening" card: 148pt square cover, author subtitle, and a progress bar along the bottom of the
/// cover for podcasts/audiobooks when `item.progress` is non-nil and > 0. The item type picks the route and the
/// fallback subtitle ("Artist", "Album", "Podcast", "Audiobook").
struct ContinueCard: View {
    let item: RecentlyListenedItem
    let onTap: () -> Void
    /// The corner play badge plays the item; the rest of the card opens it.
    let onPlay: () -> Void
    /// Card width — the caller can shrink this for a "supporting cast" rail sitting under a
    /// larger spotlight card (see `ContinueListeningSection`). Defaults to the original size.
    var cardWidth: CGFloat = 148
    /// The play request for this item is in flight: the badge spins and ignores repeat taps.
    var isBusy: Bool = false

    private let cornerRadius: CGFloat = KimaRadius.image

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                ZStack(alignment: .bottomTrailing) {
                    CoverArtImage(coverId: item.coverId, size: 256, cornerRadius: cornerRadius, placeholderSymbol: item.placeholderSymbol)
                        .aspectRatio(1, contentMode: .fill)
                        .frame(width: cardWidth, height: cardWidth)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            if item.hasPlaybackProgress, let pct = item.progress {
                                progressBar(pct: pct)
                            }
                        }
                        .kimaSleeveElevation(cornerRadius: cornerRadius)

                    CoverPlayBadge(isBusy: isBusy, action: onPlay)
                        // Same as the spotlight card: this explicit label replaces the merged
                        // "loading" text, so the busy state is composed into it.
                        .accessibilityLabel(isBusy ? "loading \(item.displayTitle)" : "play \(item.displayTitle)")
                        .padding(KimaSpacing.xs)
                }

                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    Text(item.displayTitle.lowercased())
                        .font(KimaType.captionStrong)
                        .foregroundStyle(KimaColor.textPrimary)
                        .lineLimit(1)
                    Text(item.homeSubtitle.lowercased())
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, KimaSpacing.xs)
            }
            .frame(width: cardWidth)
        }
        .buttonStyle(.kimaCard)
    }

    private func progressBar(pct: Double) -> some View {
        KimaProgressBar(fraction: pct / 100, track: Color.black.opacity(0.4))
            .padding(KimaSpacing.xs)
    }
}
