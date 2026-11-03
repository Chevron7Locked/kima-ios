import SwiftUI

// MARK: - MoodType UI config (view-layer extensions)

private extension MoodType {
    /// Same names as the server's mix names ("Upbeat Mix", "Calm Mix").
    var label: String {
        switch self {
        case .happy:      "upbeat"
        case .party:      "energetic"
        case .chill:      "calm"
        case .sad:        "melancholic"
        case .aggressive: "intense"
        }
    }

    /// Gradient stop colors sourced from `VibeMoodPalette` so each tile matches the
    /// Vibe Map and Filament accent exactly.
    var gradientColors: (Color, Color) {
        VibeMoodPalette.gradient(for: paletteMoodKey)
    }

    /// The server's own mood → field mapping (chill → moodRelaxed).
    private var paletteMoodKey: String {
        switch self {
        case .happy:      "moodHappy"
        case .party:      "moodParty"
        case .chill:      "moodRelaxed"
        case .sad:        "moodSad"
        case .aggressive: "moodAggressive"
        }
    }
}

// Display order of the mood grid.
private let moodDisplayOrder: [MoodType] = [.happy, .party, .chill, .sad, .aggressive]

/// Below this the server answers 400 "Not enough tracks" (moodBucketService getMoodMix);
/// the web disables the tile at the same line.
private let minTracksPerMood = 8

// MARK: - MoodMixerView

/// Mood Mixer sheet: pick a mood, play its mix, save the played ids,
/// reload the Home mixes rail. Moods with fewer than 8 tracks are disabled.
struct MoodMixerView: View {
    /// Reloads the Home mixes rail after a mood mix is saved (the saved mix joins GET /mixes).
    let onMixesReload: () async -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var presets: [MoodBucketPreset] = []
    @State private var loadingPresets = true
    @State private var generatingMood: MoodType? = nil

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            KimaHairline()
                .padding(.horizontal, KimaSpacing.lg)
            sheetContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KimaColor.base.ignoresSafeArea())
        .task { await loadPresets() }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: KimaSpacing.md) {
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text("mood mixer")
                    .font(KimaType.pageTitle)
                    .tracking(-0.4)
                    .foregroundStyle(KimaColor.textPrimary)
                Text("play a mix by mood")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
            }

            Spacer()

            KimaCloseButton(label: "close", id: "moodmixer-close", kind: .screen) { dismiss() }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.lg)
    }

    // MARK: - Content

    @ViewBuilder
    private var sheetContent: some View {
        if loadingPresets {
            KimaLoadingState()
        } else {
            ScrollView {
                VStack(spacing: KimaSpacing.xl) {
                    moodGrid
                    Text(footerText)
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, KimaSpacing.lg)
                }
                .padding(KimaSpacing.lg)
            }
        }
    }

    /// While analysis is still running, say how many tracks are not sorted into moods yet
    /// (web shows the same count); otherwise the standing note.
    private var footerText: String {
        let pending = presets.first?.pendingTracks ?? 0
        return pending > 0
            ? "\(pending) tracks not analysed yet"
            : "moods are based on audio analysis of your library"
    }

    // MARK: - Mood grid

    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: KimaSpacing.md),
        count: 3
    )

    private var moodGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: KimaSpacing.md) {
            ForEach(moodDisplayOrder, id: \.self) { mood in
                moodCell(mood: mood)
            }
        }
    }

    // MARK: - Mood cell

    @ViewBuilder
    private func moodCell(mood: MoodType) -> some View {
        let count = presets.first(where: { $0.id == mood.rawValue })?.trackCount ?? 0
        let isDisabled = count < minTracksPerMood
        let isGenerating = generatingMood == mood
        let (colorA, colorB) = mood.gradientColors

        Button {
            guard generatingMood == nil, !isDisabled else { return }
            Task { await generateMix(mood: mood) }
        } label: {
            // A dark tile lit by its mood colour from one corner, with a faint edge in the same colour; the
            // name and count sit bottom-left, a spinner top-right while the mix is made.
            ZStack(alignment: .topTrailing) {
                KimaColor.surface
                RadialGradient(
                    colors: [colorA.opacity(0.55), colorB.opacity(0.16), .clear],
                    center: .topTrailing,
                    startRadius: 4,
                    endRadius: 150
                )
                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    Spacer(minLength: 0)
                    Text(mood.label)
                        .font(KimaType.headline)
                        .foregroundStyle(KimaColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(count == 1 ? "1 track" : "\(count) tracks")
                        .font(KimaType.meta.monospacedDigit())
                        .foregroundStyle(KimaColor.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(KimaSpacing.md)
                if isGenerating {
                    ProgressView().tint(KimaColor.textPrimary).padding(KimaSpacing.md)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                    .strokeBorder(colorA.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(generatingMood != nil || isDisabled)
        .opacity(isDisabled ? 0.38 : 1)
        .scaleEffect(isGenerating && !reduceMotion ? 0.95 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: isGenerating)
        .accessibilityIdentifier("mood-\(mood.rawValue)")
    }

    // MARK: - Async actions

    private func loadPresets() async {
        loadingPresets = true
        defer { loadingPresets = false }
        do {
            presets = try await env.client.getMoodBucketPresets()
        } catch {
            toast.show("couldn't load moods", style: .error)
        }
    }

    private func generateMix(mood: MoodType) async {
        generatingMood = mood
        defer { generatingMood = nil }
        do {
            let mix = try await env.client.getMoodBucketMix(mood: mood)
            let tracks = (mix.tracks ?? []).map { $0.asTrack() }
            guard !tracks.isEmpty else {
                toast.show("not enough tracks for this mood", style: .error)
                return
            }

            player.play(tracks: tracks, startAt: 0)

            // Save what is playing as the user's mood mix. Best-effort: playback already runs.
            try? await env.client.saveMoodBucketMix(mood: mood, trackIds: tracks.map(\.id))

            toast.show("playing \(mood.label) mix (\(tracks.count) \(tracks.count == 1 ? "track" : "tracks"))", style: .success)
            await onMixesReload()
            dismiss()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            toast.show(msg, style: .error)
        }
    }
}
