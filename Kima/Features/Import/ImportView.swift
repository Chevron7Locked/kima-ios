import SwiftUI

// MARK: - ImportView

/// Sheet for importing a playlist from Spotify, Deezer, YouTube, SoundCloud and others: paste a
/// URL, preview counts, name it, confirm. Progress shows in Activity via the import:progress SSE.
/// `prefillURL` starts the field filled in (import from a featured playlist's page).
struct ImportView: View {
    var prefillURL: String? = nil

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var vm = ImportViewModel()

    // Keyboard dismissal: the keyboard can always be put away.
    private enum Field { case url, name }
    @FocusState private var focusedField: Field?

    var body: some View {
        content
            .task { await env.acquire.refresh(client: env.client) }
    }

    private var content: some View {
        ZStack {
            KimaScreenGround()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        urlSection
                        contentSection
                            .padding(.top, KimaSpacing.lg)
                        Spacer(minLength: KimaSpacing.huge)
                    }
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.bottom, KimaSpacing.huge)
                }
                .scrollBounceBehavior(.basedOnSize)
                .kimaKeyboardSafeCanvas()
                ImportBottomBar(vm: vm)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if let prefillURL, vm.urlText.isEmpty { vm.urlText = prefillURL }
        }
        .onDisappear { vm.stop() }   // cancel the preview poll if the sheet is dismissed mid-flight
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: KimaSpacing.sm) {
            KimaScreenTitle(title: "import playlist")
            Spacer(minLength: 0)
            KimaCloseButton(label: "close", id: "import-close", kind: .screen) { dismiss() }
        }
        .padding(.top, KimaSpacing.xs)
    }

    // MARK: - URL field

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            Text("paste a link")
                .font(KimaType.meta).foregroundStyle(KimaColor.textMuted).tracking(0)
                .padding(.top, KimaSpacing.lg)

            HStack(spacing: KimaSpacing.sm) {
                TextField("Spotify, Deezer, YouTube, SoundCloud…", text: $vm.urlText)
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .focused($focusedField, equals: .url)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .padding(.horizontal, KimaSpacing.md)
                    .frame(height: 44)
                    .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(KimaColor.hairline, lineWidth: 1))
                    .disabled(vm.isBusy || vm.isDone)

                if !vm.isBusy && !vm.isDone {
                    Button {
                        vm.startPreview(using: env.client)
                    } label: {
                        Text("preview")
                            .font(KimaType.captionStrong).tracking(0)
                            .foregroundStyle(vm.canStartPreview ? KimaColor.base : KimaColor.textMuted)
                            .fixedSize()   // the label sets the width; a fixed 48pt clipped it
                            .padding(.horizontal, KimaSpacing.md)
                            .frame(height: 44)
                            .background(
                                vm.canStartPreview ? KimaColor.brand : KimaColor.surface,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(vm.canStartPreview ? Color.clear : KimaColor.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.canStartPreview)
                }
            }
        }
    }

    // MARK: - Content area (state-driven)

    @ViewBuilder
    private var contentSection: some View {
        switch vm.state {
        case .previewing:
            previewingIndicator
        case .previewReady, .confirming:
            if let preview = vm.previewResult {
                previewReadySection(preview: preview)
            }
        case .done:
            doneState
        case .error(let msg):
            errorCard(message: msg)
        case .idle:
            EmptyView()
        }
    }

    private var previewingIndicator: some View {
        VStack(spacing: KimaSpacing.md) {
            ProgressView().tint(KimaColor.brand)
            Text("matching tracks…")
                .font(KimaType.meta).foregroundStyle(KimaColor.textMuted).tracking(0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KimaSpacing.xl)
    }

    private func previewReadySection(preview: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.lg) {
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text("matched")
                    .font(KimaType.meta).foregroundStyle(KimaColor.textMuted).tracking(0)
                Text(preview.playlist.name.lowercased())
                    .font(KimaType.bodyStrong)
                    .foregroundStyle(KimaColor.textPrimary).lineLimit(2)
                Text("by \(preview.playlist.owner)  ·  \(preview.playlist.trackCount) \(preview.playlist.trackCount == 1 ? "track" : "tracks")")
                    .font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
            }

            HStack(spacing: KimaSpacing.sm) {
                KimaStatTile(value: "\(preview.summary.inLibrary)", label: "in library", tint: KimaColor.textSecondary)
                KimaStatTile(value: "\(preview.summary.downloadable)",
                             label: env.acquire.canAcquire ? "to download" : "not in library")
                KimaStatTile(value: "\(preview.summary.notFound)", label: "not found", tint: KimaColor.danger)
            }

            VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                Text("playlist name")
                    .font(KimaType.meta).foregroundStyle(KimaColor.textMuted).tracking(0)
                TextField("playlist name", text: $vm.playlistName)
                    .font(KimaType.body).foregroundStyle(KimaColor.textPrimary)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .name)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .padding(.horizontal, KimaSpacing.md).frame(height: 44)
                    .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(KimaColor.hairline, lineWidth: 1))
                    .disabled(vm.isBusy)
            }

            if !env.acquire.canAcquire, preview.summary.downloadable > 0 {
                Text(AcquirePermission.lockedLabel)
                    .font(KimaType.meta)
                    .foregroundStyle(KimaColor.textMuted)
            } else if !preview.albumsToDownload.isEmpty {
                let n = preview.albumsToDownload.count
                Text("\(n) album\(n == 1 ? "" : "s") will be downloaded — track progress in activity")
                    .font(KimaType.meta)
                    .foregroundStyle(KimaColor.textMuted)
                    .tracking(0)
                    .lineLimit(2)
            }
        }
    }

    private var doneState: some View {
        VStack(spacing: KimaSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(KimaColor.positive)
            Text("import started")
                .font(KimaType.caption).foregroundStyle(KimaColor.textPrimary).tracking(0)
            Text("track progress in activity (bell icon)")
                .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KimaSpacing.xl)
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            HStack(spacing: KimaSpacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(KimaColor.danger)
                Text("import failed")
                    .font(KimaType.meta).foregroundStyle(KimaColor.danger).tracking(0)
            }
            Text(message)
                .font(KimaType.caption).foregroundStyle(KimaColor.textMuted).lineLimit(3)
        }
        .padding(KimaSpacing.md)
        .background(KimaColor.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(KimaColor.danger.opacity(0.2), lineWidth: 1))
    }
}
