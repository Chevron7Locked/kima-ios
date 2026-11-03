import SwiftUI

// MARK: - AudiobookActionBar

/// Action bar for AudiobookDetailView: Play/Pause button, live progress bar, mark as finished / listen again,
/// and a "•••" menu holding reset progress. Reset and mark as finished each toast with an undo. Reads player
/// state from the environment, so it stays live without view model coupling.
struct AudiobookActionBar: View {
    let book: Audiobook
    /// VM ref — @Observable class, body auto-tracks relevant reads.
    let vm: AudiobookDetailViewModel

    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    // MARK: Derived state

    private var isThisBookLoaded: Bool { env.player.isAudiobookLoaded(book.id) }

    private var isThisBookPlaying: Bool {
        isThisBookLoaded && env.player.isPlaying
    }

    private var storedProgress: AudiobookProgress? { book.progress }
    private var isInProgress: Bool {
        (storedProgress?.progress ?? 0) > 0 && !(storedProgress?.isFinished ?? false)
    }
    private var isFinished: Bool { storedProgress?.isFinished ?? false }

    /// Live fraction (0–1) when this book is in the player; falls back to stored value.
    private var progressFraction: Double {
        if isThisBookLoaded {
            let d = env.player.duration
            return d > 0 ? env.player.currentTime / d : 0
        }
        return vm.storedProgressFraction
    }

    private var currentDisplayTime: Double {
        isThisBookLoaded ? env.player.currentTime : (storedProgress?.currentTime ?? 0)
    }


    // MARK: Body

    var body: some View {
        VStack(spacing: KimaSpacing.lg) {
            playButton
            if isInProgress || isThisBookLoaded { progressStack }
            secondaryActions
        }
    }

    // MARK: Play / Pause

    private var playButton: some View {
        Button {
            if isThisBookLoaded {
                if env.player.isPlaying { env.player.pause() } else { env.player.resume() }
            } else {
                Task { await env.player.playAudiobook(book, client: env.client) }
            }
        } label: {
            HStack(spacing: KimaSpacing.sm) {
                Image(systemName: isThisBookPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text(playLabel)
                    .font(KimaType.headline)
                    .tracking(0.1)
            }
            .foregroundStyle(KimaColor.onBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, KimaSpacing.lg)
            .background(Capsule().fill(KimaColor.brand))
        }
        .buttonStyle(.plain)
    }

    private var playLabel: String {
        if isThisBookPlaying { return "pause" }
        return isInProgress ? "resume" : "play"
    }

    // MARK: Progress bar + timestamps

    private var progressStack: some View {
        VStack(spacing: KimaSpacing.xs) {
            KimaProgressBar(fraction: progressFraction, height: 4)
            HStack {
                Text(currentDisplayTime.durationFormatted)
                    .font(KimaType.caption.monospacedDigit())
                    .foregroundStyle(KimaColor.textMuted)
                Spacer()
                Text(book.duration.lengthLabel)
                    .font(KimaType.caption.monospacedDigit())
                    .foregroundStyle(KimaColor.textMuted)
            }
        }
    }

    // MARK: Reset / Mark Done / Listen Again

    @ViewBuilder
    private var secondaryActions: some View {
        // Reading isResettingProgress + isMarkingComplete here registers them with SwiftUI
        // observation so the disabled state updates when in-flight tasks complete.
        let busy = vm.isResettingProgress || vm.isMarkingComplete
        HStack(spacing: KimaSpacing.md) {
            if isFinished {
                // "Listen Again" — resets progress so user can restart
                secondaryButton(title: "listen again", icon: "arrow.counterclockwise",
                                isLoading: vm.isResettingProgress) { reset(done: "ready to listen again") }
            } else {
                secondaryButton(title: "mark as finished", icon: "checkmark.circle",
                                isLoading: vm.isMarkingComplete) { markFinished() }
            }

            // Reset sits in a menu, never one tap from resume.
            if isInProgress {
                KimaMoreMenu(label: "more book actions", isWorking: vm.isResettingProgress) {
                    Button("reset progress", systemImage: "arrow.counterclockwise", role: .destructive) {
                        reset(done: "progress reset")
                    }
                }
            }
        }
        .disabled(busy)
    }

    private func reset(done message: String) {
        Task {
            do {
                let previous = try await vm.resetProgress(client: env.client)
                toast.show(message, style: .success, action: undo(previous))
            } catch {
                toast.show(error.localizedDescription, style: .error)
            }
        }
    }

    private func markFinished() {
        Task {
            do {
                let previous = try await vm.markComplete(client: env.client)
                toast.show("marked as finished", style: .success, action: undo(previous))
            } catch {
                toast.show(error.localizedDescription, style: .error)
            }
        }
    }

    /// The toast's undo: puts back the progress the action replaced.
    private func undo(_ previous: AudiobookProgress?) -> ToastAction {
        ToastAction(label: "undo") { [vm, env, toast] in
            Task {
                do {
                    try await vm.restoreProgress(previous, client: env.client)
                    toast.show("progress put back", style: .success)
                } catch {
                    toast.show("couldn't put your progress back", style: .error)
                }
            }
        }
    }

    private func secondaryButton(
        title: String,
        icon: String,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: KimaSpacing.xs) {
                if isLoading {
                    ProgressView().scaleEffect(0.7).tint(KimaColor.textMuted)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(KimaType.caption)
            .foregroundStyle(KimaColor.textSecondary)
            .padding(.horizontal, KimaSpacing.md)
            .padding(.vertical, KimaSpacing.sm)
            .background(KimaColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(KimaColor.hairline, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SeriesBlock

/// Series name + sequence number block at the bottom of the detail view; opens the series page.
struct SeriesBlock: View {
    let series: AudiobookSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "series")
            NavigationLink {
                AudiobookSeriesView(name: series.name)
            } label: {
                HStack(spacing: KimaSpacing.md) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 20))
                        .foregroundStyle(KimaColor.textMuted)
                    VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                        Text(series.name.lowercased())
                            .font(KimaType.headline)
                            .foregroundStyle(KimaColor.textPrimary)
                        Text("book \(series.sequence)")
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textMuted)
                    }
                    Spacer(minLength: KimaSpacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KimaColor.textMuted)
                }
                .padding(.horizontal, KimaSpacing.lg)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("open the series \(series.name)")
        }
    }
}
