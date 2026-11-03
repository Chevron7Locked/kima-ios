import SwiftUI

/// Song path as one flow: the start, then the end, each a star tapped on the map or a search pick; one
/// prompt at a time, then "generate path". Opened from a star, the start is already filled. "swap" at
/// the header's end trades the ends. Once both are set a star tap selects it, and the panel offers
/// "set as start" and "set as end" for it.
struct VibeSongPathPanel: View {
    let vm: VibeMapViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player

    @State private var text = ""
    @State private var focused = false
    @State private var finder = VibeTrackFinder()
    @State private var isGenerating = false

    private var form: VibeSongPathForm { vm.songPath }

    /// Room for the longest row label, "selected", so the titles line up.
    private static let labelWidth: CGFloat = 56

    var body: some View {
        VibePanelCard(title: "song path") {
            if form.start != nil || form.end != nil { swapButton }
        } content: {
            VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                if let start = form.start { endRow("start", start, slot: .start) }
                if let end = form.end { endRow("end", end, slot: .end) }
                if let candidate = vm.pathCandidate { candidateRows(candidate) }
                if let slot = form.nextSlot {
                    KimaSearchField(prompt: slot == .start ? "start: tap a star or search" : "end: tap a star or search",
                                    submitLabel: .return, text: $text, isFocused: $focused)
                        .accessibilityIdentifier(slot == .start ? "vibe-path-start" : "vibe-path-end")
                    VibeFinderResults(finder: finder, maxHeight: focused ? .infinity : 220, onPick: pick)
                }
                if form.sameTrack {
                    VibePanelNote("pick a different track for the end.")
                }
                if let error = vm.modeError { VibeErrorLine(error, id: "vibe-panel-error") }
                Button(action: generate) {
                    VibePanelButtonLabel(title: isGenerating ? "generating…" : "generate path")
                }
                .buttonStyle(.kimaCard)
                .disabled(!form.canGenerate || isGenerating)
                .accessibilityIdentifier("vibe-path-generate")
            }
        }
        .task(id: text) {
            await finder.search(text, index: vm.libraryIndex, client: env.client)
        }
        .onChange(of: form.nextSlot) { _, _ in text = "" }
        #if DEBUG
        .onAppear {
            // Screenshot hook: types into the field once the map's name index is built.
            if let t = UserDefaults.standard.string(forKey: "kima-vibe-type") {
                Task { try? await Task.sleep(for: .seconds(1.5)); text = t; focused = true }
            }
        }
        #endif
    }

    /// Trades the start and the end; with one end set, it moves to the other side.
    private var swapButton: some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { vm.songPath.swap() } } label: {
            HStack(spacing: KimaSpacing.xs) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 10, weight: .semibold))
                Text("swap").font(KimaType.caption)
            }
            .foregroundStyle(KimaColor.textSecondary)
            .kimaHitTarget(growsLayout: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("swap start and end")
        .accessibilityIdentifier("vibe-path-swap")
    }

    /// The selected star, with "set as start" and "set as end" under its name.
    private func candidateRows(_ candidate: VibeTrackPick) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VibePickRow(label: "selected", labelWidth: Self.labelWidth, pick: candidate, id: "vibe-path-candidate") {
                EmptyView()
            }
            // Side by side, or one over the other when large text leaves no room.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: KimaSpacing.sm) { setAsButtons }
                VStack(alignment: .leading, spacing: 0) { setAsButtons }
            }
            .padding(.leading, Self.labelWidth + KimaSpacing.md)
        }
    }

    @ViewBuilder private var setAsButtons: some View {
        setAs("set as start", slot: .start, id: "vibe-path-set-start")
        setAs("set as end", slot: .end, id: "vibe-path-set-end")
    }

    private func setAs(_ title: String, slot: VibeSongPathForm.Slot, id: String) -> some View {
        Button { vm.setSelected(as: slot) } label: {
            Text(title)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, KimaSpacing.md)
                .frame(height: 30)
                .kimaOutline(Capsule())
                .frame(minHeight: KimaLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.kimaCard)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityIdentifier(id)
    }

    /// A filled end: "start"/"end", the track, and a × that empties it to pick again.
    private func endRow(_ label: String, _ pick: VibeTrackPick, slot: VibeSongPathForm.Slot) -> some View {
        VibePickRow(label: label, labelWidth: Self.labelWidth, pick: pick, id: "vibe-path-\(label)-pick") {
            KimaCloseButton(label: "change the \(label)", id: "vibe-path-\(label)-clear") { vm.songPath.clear(slot) }
        }
    }

    private func pick(_ item: VibeTrackFinder.Item) {
        vm.songPath.fill(VibeTrackPick(id: item.id, title: item.title, artist: item.artist))
        vm.modeError = nil
        text = ""
        // Keyboard down, so the map is in view for tapping the other end.
        focused = false
    }

    private func generate() {
        guard let start = form.start?.id, let end = form.end?.id, form.canGenerate else { return }
        isGenerating = true
        vm.modeError = nil
        vm.launch {
            let ok = await vm.finishSongPath(from: start, to: end, client: env.client, player: player)
            isGenerating = false
            if ok { vm.panel = nil }
        }
    }
}
