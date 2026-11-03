import SwiftUI

// MARK: - Changelog

/// Every server release, newest first: its summary, the maintainer's note, and each item with what the server
/// knows about it — the answer recorded, the action really done, or "open" until it is. Reading writes nothing.
/// Items expand in place to their full text; answering and running stay in the release window.
struct ChangelogView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var phase: LoadPhase<WhatsNewChangelog> = .loading
    @State private var expanded: Set<String> = []

    var body: some View {
        Group {
            switch phase {
            case .loading:
                KimaLoadingState(onRetry: { Task { await load() } })
            case .failed:
                KimaErrorState(message: "couldn't load the changelog") { Task { await load() } }
            case .loaded(let changelog):
                content(changelog)
            }
        }
        .kimaScreenCanvas()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Read again on every visit: an item can settle on the server between visits.
        .task { await load() }
    }

    private func load() async {
        if !phase.isLoaded { phase = .loading }
        do { phase = .loaded(try await env.client.getChangelog()) }
        catch { if !phase.isLoaded { phase = .failed(error.localizedDescription) } }
    }

    private func content(_ changelog: WhatsNewChangelog) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                KimaScreenHeader(title: "changelog")

                let open = changelog.releases.flatMap { r in r.items.filter { $0.open == true }.map { (r, $0) } }
                if !open.isEmpty {
                    stillOpen(open)
                }

                ForEach(Array(changelog.releases.enumerated()), id: \.element.id) { index, release in
                    releaseSection(release, isFirst: index == 0 && open.isEmpty)
                }

                Spacer(minLength: KimaSpacing.lg)
            }
        }
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
        .refreshable { await load() }
    }

    // MARK: - Still open

    private func stillOpen(_ open: [(WhatsNewRelease, WhatsNewItem)]) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            Text("still open")
                .font(KimaType.section)
                .foregroundStyle(KimaColor.textPrimary)
            ForEach(open, id: \.1.key) { release, item in
                Text("\(item.title.lowercased()) · from \(release.shortVersion)")
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.bottom, KimaSpacing.xl)
    }

    // MARK: - Release

    private func releaseSection(_ release: WhatsNewRelease, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            if !isFirst {
                KimaHairline()
                    .padding(.bottom, KimaSpacing.md)
            }

            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text(release.title.lowercased())
                    .font(KimaType.section)
                    .foregroundStyle(KimaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(releaseMeta(release))
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
            }

            if !release.summary.isEmpty {
                Text(release.summary.lowercasedFirstSentence())
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note = release.note, !note.body.isEmpty {
                VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                    Text("note from \(note.from.lowercased())")
                        .font(KimaType.captionStrong)
                        .foregroundStyle(KimaColor.textPrimary)
                    WhatsNewItemBody(text: note.body)
                }
                .padding(.top, KimaSpacing.sm)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(release.items) { item in
                    itemRow(item, in: release)
                }
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.bottom, KimaSpacing.xxl)
    }

    private func releaseMeta(_ release: WhatsNewRelease) -> String {
        let date = Self.dayParser.date(from: release.date).map { Formatters.monthDayYear.string(from: $0).lowercased() }
        return ["v\(release.version)", date].compactMap { $0 }.joined(separator: " · ")
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Item

    private func itemRow(_ item: WhatsNewItem, in release: WhatsNewRelease) -> some View {
        let key = "\(release.version)/\(item.key)"
        let isOpen = expanded.contains(key)
        return VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if isOpen { expanded.remove(key) } else { expanded.insert(key) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.md) {
                    VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                        Text(item.title.lowercasedFirstSentence())
                            .font(KimaType.bodyStrong)
                            .foregroundStyle(KimaColor.textPrimary)
                        if !item.summary.isEmpty {
                            Text(item.summary.lowercasedFirstSentence())
                                .font(KimaType.caption)
                                .foregroundStyle(KimaColor.textMuted)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let state = Self.stateLabel(item) {
                        Text(state.text)
                            .font(KimaType.metaStrong)
                            .foregroundStyle(state.isOpen ? KimaColor.textPrimary : KimaColor.textMuted)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(KimaColor.textMuted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, KimaSpacing.md)
                .frame(minHeight: KimaLayout.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "hides the details" : "shows the details")

            if isOpen {
                VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                    WhatsNewItemBody(text: item.body)
                    if item.kind == .choice, item.answer == nil {
                        Text("not answered · stays off")
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textMuted)
                    }
                    if item.open == true, let ifClosed = item.ifClosed {
                        Text(ifClosed.lowercasedFirstSentence())
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, KimaSpacing.md)
                .transition(.opacity)
            }
        }
    }

    /// "open" while the server cannot see an action done, "done" once it can, a choice's recorded answer otherwise.
    static func stateLabel(_ item: WhatsNewItem) -> (text: String, isOpen: Bool)? {
        if item.open == true { return ("open", true) }
        if item.done == true { return ("done", false) }
        if let answer = item.answer {
            let said = answer.enabled ? "on" : "off"
            return (answer.isExplicit ? "you said \(said)" : "\(said) · unanswered", false)
        }
        return nil
    }
}
