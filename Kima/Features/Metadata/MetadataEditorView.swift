import SwiftUI

// Plex/Kavita-style metadata editor sheet — one component handles all three entity types
// (artist / album / track) using MetadataEntityKind to gate per-type fields.

struct MetadataEditorView: View {
    let kind: MetadataEntityKind
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self) private var toast

    @State private var vm: MetadataEditorViewModel

    // Keyboard dismissal (rule: always be able to remove the keyboard).
    private enum Field { case name, bio, year, genres, mbid, imageURL, trackNo }
    @FocusState private var focusedField: Field?

    init(kind: MetadataEntityKind, onSaved: @escaping () -> Void) {
        self.kind = kind
        self.onSaved = onSaved
        _vm = State(wrappedValue: MetadataEditorViewModel(kind: kind))
    }

    var body: some View {
        ZStack {
            KimaScreenGround()

            VStack(spacing: 0) {
                header
                    .padding(.top, KimaSpacing.sm)
                KimaHairline().padding(.horizontal, KimaSpacing.lg)
                formContent
                KimaHairline().padding(.horizontal, KimaSpacing.lg)
                footer
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KimaColor.base)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("edit \(vm.entityLabel) metadata")
                .font(KimaType.pageTitle)
                .foregroundStyle(KimaColor.textPrimary)
                .tracking(-0.3)
            Spacer()
            KimaCloseButton(label: "close", id: "metadata-close", kind: .screen) { dismiss() }
                .disabled(vm.isSaving || vm.isResetting)
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.lg)
    }

    // MARK: - Form

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KimaSpacing.xl) {

                // Name / Title — all entity types
                field(label: vm.nameLabel, hint: vm.originalNameOrTitle.map { "original: \($0)" }) {
                    TextField(vm.nameLabel, text: $vm.nameOrTitle,
                              prompt: Text.kimaPrompt(vm.nameLabel))
                        .kimaField()
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }

                // Biography — artist only
                if case .artist = kind {
                    field(label: "biography",
                          hint: vm.originalBio.map { "original: \(String($0.prefix(100)))…" }) {
                        TextField("biography", text: $vm.bio, axis: .vertical)
                            .lineLimit(4...8)
                            .kimaField()
                            .focused($focusedField, equals: .bio)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }
                }

                // Release year — album only
                if case .album = kind {
                    field(label: "release year",
                          hint: vm.originalYear.map { "original: \($0)" }) {
                        TextField("release year", text: $vm.year,
                                  prompt: Text.kimaPrompt("e.g. 2024"))
                            .kimaField()
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .year)
                    }
                }

                // Genres — artist + album
                switch kind {
                case .artist, .album:
                    field(label: "genres", sublabel: "comma-separated",
                          hint: vm.originalGenres.map { "original: \($0)" }) {
                        TextField("genres", text: $vm.genres,
                                  prompt: Text.kimaPrompt("rock, alternative, indie"))
                            .kimaField()
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .genres)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }
                default: EmptyView()
                }

                // MusicBrainz ID — artist + album
                switch kind {
                case .artist, .album:
                    field(label: vm.mbidLabel, sublabel: "leave empty to auto-fetch") {
                        TextField(vm.mbidLabel, text: $vm.mbidOrRgMbid,
                                  prompt: Text.kimaPrompt("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"))
                            .kimaField()
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .mbid)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                            .font(KimaType.caption)
                    }
                default: EmptyView()
                }

                // Image URL — artist + album
                switch kind {
                case .artist, .album:
                    field(label: vm.imageLabel, sublabel: "leave empty to auto-fetch",
                          hint: vm.originalImageUrl.map { "original: \($0)" }) {
                        TextField("image url", text: $vm.imageUrl,
                                  prompt: Text.kimaPrompt("https://…"))
                            .kimaField()
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .focused($focusedField, equals: .imageURL)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }
                default: EmptyView()
                }

                // Track number — track only
                if case .track = kind {
                    field(label: "track number") {
                        TextField("track #", text: $vm.trackNo,
                                  prompt: Text.kimaPrompt("e.g. 3"))
                            .kimaField()
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .trackNo)
                    }
                }

                overrideNote

                // Destructive, so it sits alone at the foot of the form, never beside save.
                if vm.hasUserOverrides {
                    KimaDestructiveRow(
                        label: "reset",
                        confirmTitle: "reset all metadata to original values? this cannot be undone.",
                        confirmButton: "reset to original",
                        isBusy: vm.isResetting,
                        busyLabel: "resetting…",
                        gutter: 0,
                        topGap: KimaSpacing.huge - KimaSpacing.xl
                    ) {
                        Task { await performReset() }
                    }
                    .disabled(vm.isSaving)
                }
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.vertical, KimaSpacing.xl)
        }
        .kimaKeyboardSafeCanvas()
    }

    // MARK: - Field helper

    @ViewBuilder
    private func field(label: String, sublabel: String? = nil, hint: String? = nil,
                       @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.xs) {
                Text(label)
                    .font(KimaType.headline)
                    .foregroundStyle(KimaColor.textPrimary)
                if let sublabel {
                    Text("(\(sublabel))")
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                }
            }
            content()
            if let hint {
                Text(hint)
                    .font(KimaType.meta)
                    .foregroundStyle(KimaColor.textMuted)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
    }

    // MARK: - Override note

    private var overrideNote: some View {
        HStack(alignment: .top, spacing: KimaSpacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(KimaColor.textMuted)
            Text("your edits won't be overwritten by automatic updates.")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KimaSpacing.lg)
        .background(KimaColor.fillQuiet, in: RoundedRectangle(cornerRadius: KimaRadius.card))
        .overlay(RoundedRectangle(cornerRadius: KimaRadius.card)
            .strokeBorder(KimaColor.hairline, lineWidth: 1))
    }

    // MARK: - Footer

    private var footer: some View {
        // Cancel at its natural width; save takes the rest, so its label always fits.
        HStack(spacing: KimaSpacing.md) {
            Button { dismiss() } label: {
                Text("cancel")
                    .font(KimaType.headline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(KimaColor.textSecondary)
                    .padding(.horizontal, KimaSpacing.lg)
                    .padding(.vertical, KimaSpacing.lg)
                    .background(KimaColor.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(vm.isSaving || vm.isResetting)

            KimaPrimaryButton(
                title: "save changes",
                isLoading: vm.isSaving,
                systemImage: vm.isSaving ? nil : "checkmark"
            ) {
                Task { await performSave() }
            }
            .disabled(vm.isResetting)
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.lg)
    }

    // MARK: - Actions

    private func performSave() async {
        do {
            if try await vm.save(client: env.client) {
                toast.show("\(vm.entityLabel) metadata updated", style: .success)
                onSaved()
            }
            dismiss()
        } catch {
            toast.show(error.localizedDescription, style: .error)
            // Sheet stays open so the user can correct and retry
        }
    }

    private func performReset() async {
        do {
            try await vm.reset(client: env.client)
            toast.show("metadata reset to original values", style: .success)
            onSaved()
            dismiss()
        } catch {
            toast.show(error.localizedDescription, style: .error)
        }
    }
}
