import SwiftUI

/// Blend: one line per side ("more like · 2"; tap it to see and remove its
/// tracks), one search field that adds to the side picked at its start, then blend, look at the
/// list and play it. The readout's "more like" and "less like" and the rail (with a star selected)
/// add picks too.
struct VibeBlendPanel: View {
    let vm: VibeMapViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackController.self) private var player

    @State private var column: VibeBlendPicks.Column = .more
    /// The side whose tracks are listed under its line.
    @State private var expanded: VibeBlendPicks.Column?
    @State private var text = ""
    @State private var focused = false
    @State private var finder = VibeTrackFinder()

    var body: some View {
        VibePanelCard(title: "blend") {
            VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    side(.more, list: vm.blendPicks.more)
                    side(.less, list: vm.blendPicks.less)
                }
                KimaSearchField(prompt: "add a track", submitLabel: .return, text: $text, isFocused: $focused) {
                    sideMenu
                }
                .accessibilityIdentifier("vibe-blend-search")
                VibeFinderResults(finder: finder, maxHeight: focused ? .infinity : 220, onPick: add)
                if let error = vm.modeError { VibeErrorLine(error, id: "vibe-panel-error") }
                if !finder.isActive, !vm.blendResults.isEmpty { results }
                blendButton
            }
        }
        .task(id: text) {
            await finder.search(text, index: vm.libraryIndex, client: env.client)
        }
        // Typing needs the room: an open list of picks folds away.
        .onChange(of: focused) { _, now in if now { expanded = nil } }
        #if DEBUG
        .onAppear {
            // Screenshot hook: types into the field once the map's name index is built.
            if let t = UserDefaults.standard.string(forKey: "kima-vibe-type") {
                Task { try? await Task.sleep(for: .seconds(1.5)); text = t; focused = true }
            }
        }
        #endif
    }

    // MARK: Sides

    private static func name(_ c: VibeBlendPicks.Column) -> String { c == .more ? "more like" : "less like" }

    /// One side on one line, "more like · 2". With tracks, a tap lists them under it, each with a ×.
    @ViewBuilder
    private func side(_ c: VibeBlendPicks.Column, list: [VibeTrackPick]) -> some View {
        let open = expanded == c && !list.isEmpty
        let line = HStack(spacing: KimaSpacing.sm) {
            Text("\(Self.name(c)) · \(list.count)")
                .font(KimaType.caption)
                .monospacedDigit()
                .foregroundStyle(list.isEmpty ? KimaColor.textMuted : KimaColor.textPrimary)
            if !list.isEmpty {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(KimaColor.textMuted)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: KimaLayout.minTouchTarget)
        .contentShape(Rectangle())
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        let spoken = "\(Self.name(c)), \(list.count) \(list.count == 1 ? "track" : "tracks")"
        let id = c == .more ? "vibe-blend-more" : "vibe-blend-less"
        if list.isEmpty {
            line
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                .accessibilityIdentifier(id)
        } else {
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded = open ? nil : c } } label: { line }
                .buttonStyle(.plain)
                .accessibilityLabel(spoken)
                .accessibilityValue(open ? "shown" : "hidden")
                .accessibilityIdentifier(id)
            if open {
                VibeSizedScroll(maxHeight: 176) {
                    VStack(spacing: 0) {
                        ForEach(list) { pick in
                            VibePickRow(pick: pick, id: "vibe-blend-pick") {
                                KimaCloseButton(label: "remove \(pick.title)", id: "vibe-blend-remove") {
                                    withAnimation(.easeInOut(duration: 0.2)) { vm.blendPicks.remove(pick.id, from: c) }
                                }
                            }
                        }
                    }
                }
                .padding(.leading, KimaSpacing.md)
            }
        }
    }

    /// Which side the field adds to, at the field's start: "more ▾" or "less ▾".
    private var sideMenu: some View {
        Menu {
            Picker("adds to", selection: $column) {
                Text(Self.name(.more)).tag(VibeBlendPicks.Column.more)
                Text(Self.name(.less)).tag(VibeBlendPicks.Column.less)
            }
        } label: {
            HStack(spacing: KimaSpacing.xs) {
                Text(column == .more ? "more" : "less")
                    .font(KimaType.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(KimaColor.textPrimary)
            .frame(minHeight: KimaLayout.minTouchTarget)
            .contentShape(Rectangle())
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .accessibilityLabel("adds to")
        .accessibilityValue(Self.name(column))
        .accessibilityIdentifier("vibe-blend-side")
    }

    private func add(_ item: VibeTrackFinder.Item) {
        vm.blendPicks.add(VibeTrackPick(id: item.id, title: item.title, artist: item.artist), to: column)
        text = ""
        vm.blendResults = []
    }

    // MARK: Blend + results

    private var blendButton: some View {
        Button {
            Task { await vm.runBlend(picks: vm.blendPicks, client: env.client) }
        } label: {
            VibePanelButtonLabel(title: vm.isBlending ? "blending…" : "blend")
        }
        .buttonStyle(.kimaCard)
        .disabled(!vm.blendPicks.canBlend || vm.isBlending)
        .accessibilityIdentifier("vibe-blend-go")
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { vm.launch { await vm.playBlendResult(player: player) } } label: {
                VibePanelButtonLabel(title: "play result (\(vm.blendResults.count))")
            }
            .buttonStyle(.kimaCard)
            .accessibilityIdentifier("vibe-blend-play")
            .padding(.bottom, KimaSpacing.sm)
            VibeSizedScroll {
                VStack(spacing: 0) {
                    ForEach(Array(vm.blendResults.enumerated()), id: \.element.id) { i, track in
                        HStack(spacing: KimaSpacing.md) {
                            Text("\(i + 1)")
                                .font(KimaType.meta)
                                .monospacedDigit()
                                .foregroundStyle(KimaColor.textMuted)
                                .frame(width: 22, alignment: .trailing)
                            VibeTitleDetail(title: track.title, detail: track.artist.name)
                            Spacer(minLength: 0)
                            if let s = track.similarity {
                                Text("\(Int((s * 100).rounded()))%")
                                    .font(KimaType.meta)
                                    .monospacedDigit()
                                    .foregroundStyle(KimaColor.textMuted)
                            }
                        }
                        .frame(minHeight: KimaLayout.minTouchTarget)
                        .accessibilityIdentifier("vibe-blend-result")
                    }
                }
            }
        }
    }
}
