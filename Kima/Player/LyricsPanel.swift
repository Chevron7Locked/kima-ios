import SwiftUI

// MARK: - Lyrics API model

/// Response shape for GET /api/library/tracks/:id/lyrics.
/// `syncedLyrics` is LRC-format text; `plainLyrics` is a plain-text fallback.
/// Referenced by both `LyricsPanel` and `KimaAPIClient+Library`.
struct LyricsResponse: Codable, Sendable {
    let plainLyrics: String?
    let syncedLyrics: String?
    let source: String?
}

// MARK: - LRC parser

/// A single timed lyric line parsed from an LRC file.
struct LyricLine: Identifiable, Sendable {
    let id = UUID()
    let timeMs: Int   // timestamp in milliseconds
    let text: String
}

/// Parse an LRC-format string into sorted timed lines.
///
/// Handles `[mm:ss.xx]` (centiseconds, 2 digits) and `[mm:ss.xxx]` (milliseconds, 3 digits).
/// Lines without a time tag (metadata like `[ar:Artist]`) are skipped silently.
func parseLRC(_ lrc: String) -> [LyricLine] {
    guard let regex = try? NSRegularExpression(
        pattern: #"^\[(\d{1,2}):(\d{2})\.(\d{2,3})\](.*)"#
    ) else { return [] }

    return lrc.components(separatedBy: "\n").compactMap { rawLine in
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        let nsLine = line as NSString
        guard let match = regex.firstMatch(
            in: line,
            range: NSRange(location: 0, length: nsLine.length)
        ), match.numberOfRanges == 5 else { return nil }

        func capture(_ i: Int) -> String? {
            let r = match.range(at: i)
            guard r.location != NSNotFound else { return nil }
            return nsLine.substring(with: r)
        }

        guard let minStr = capture(1), let secStr = capture(2), let msStr = capture(3),
              let min = Int(minStr), let sec = Int(secStr) else { return nil }

        var frac = Int(msStr) ?? 0
        if msStr.count == 2 { frac *= 10 }   // centiseconds → milliseconds
        let totalMs = (min * 60 + sec) * 1000 + frac

        let text = (capture(4) ?? "").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : LyricLine(timeMs: totalMs, text: text)
    }
    .sorted { $0.timeMs < $1.timeMs }
}

/// Binary-search the active lyric line for the given playback position.
/// Returns the index of the last line whose `timeMs ≤ nowMs`; nil before the first line starts
/// (the intro) and when `lines` is empty.
func activeLyricIndex(at nowMs: Int, in lines: [LyricLine]) -> Int? {
    var lo = 0, hi = lines.count - 1
    while lo <= hi {
        let mid = (lo + hi) / 2
        if lines[mid].timeMs <= nowMs { lo = mid + 1 } else { hi = mid - 1 }
    }
    return hi >= 0 ? hi : nil
}

// MARK: - LyricsPanel

/// Lyrics panel that swaps in for the artwork hero when lyrics are toggled. Fetches lyrics on track change;
/// synced (LRC) lyrics auto-scroll with the active line found by binary search on the 1 Hz `displayTime`,
/// else plain text, else an empty state. Fetch errors degrade silently to the empty state.
struct LyricsPanel: View {

    @Environment(PlaybackController.self) private var player
    @Environment(AppEnvironment.self) private var env

    // MARK: - State

    private enum LyricsState {
        case loading
        case synced([LyricLine])
        case plain(String)
        case empty
    }

    @State private var state: LyricsState = .loading

    // MARK: - Body

    var body: some View {
        ZStack {
            // Panel background — slightly elevated surface
            RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                .fill(KimaColor.surfaceRaised.opacity(0.75))

            switch state {
            case .loading:
                ProgressView().tint(KimaColor.textMuted)

            case .synced(let lines):
                syncedView(lines)

            case .plain(let text):
                plainView(text)

            case .empty:
                Text("no lyrics available")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
            }
        }
        .task(id: player.currentTrack?.id) {
            await fetchLyrics()
        }
    }

    // MARK: - Synced view

    @ViewBuilder
    private func syncedView(_ lines: [LyricLine]) -> some View {
        let nowMs     = Int(player.displayTime * 1000)
        // -1 is a safe sentinel: never a valid ForEach idx, so no line is highlighted
        // when the position precedes all lyric timestamps or lines is empty.
        let activeIdx = activeLyricIndex(at: nowMs, in: lines) ?? -1

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: KimaSpacing.md) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                        Text(line.text)
                            .font(idx == activeIdx
                                  ? KimaType.bodyStrong
                                  : KimaType.body)
                            .foregroundStyle(idx == activeIdx
                                             ? KimaColor.textPrimary
                                             : KimaColor.textMuted.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut(duration: 0.25), value: activeIdx)
                            .id(line.id)
                    }
                }
                .padding(.vertical, KimaSpacing.xxl)
                .padding(.horizontal, KimaSpacing.lg)
            }
            .mask(fadeMask)
            .onChange(of: activeIdx) { _, newIdx in
                guard newIdx >= 0, newIdx < lines.count else { return }
                withAnimation(.easeInOut(duration: 0.30)) {
                    proxy.scrollTo(lines[newIdx].id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Plain view

    @ViewBuilder
    private func plainView(_ text: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(text)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, KimaSpacing.xl)
                .padding(.horizontal, KimaSpacing.lg)
        }
        .mask(fadeMask)
    }

    // MARK: - Fade mask

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.00),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.88),
                .init(color: .clear, location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Fetch

    private func fetchLyrics() async {
        guard let trackId = player.currentTrack?.id else { state = .empty; return }
        // Cache hit — show immediately with no loading flash on reopen.
        if let cached = player.lyricsCache[trackId] {
            applyResponse(cached)
            return
        }
        state = .loading
        do {
            let resp = try await env.client.getLyrics(trackId: trackId)
            player.lyricsCache[trackId] = resp
            applyResponse(resp)
        } catch {
            state = .empty   // treat fetch errors as "no lyrics" — never surface an error toast
        }
    }

    private func applyResponse(_ resp: LyricsResponse) {
        if let synced = resp.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            state = lines.isEmpty ? .plain(synced) : .synced(lines)
        } else if let plain = resp.plainLyrics, !plain.isEmpty {
            state = .plain(plain)
        } else {
            state = .empty
        }
    }
}
