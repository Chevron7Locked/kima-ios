import SwiftUI

// MARK: - ImportBottomBar

/// `ImportView`'s state-driven bottom action bar — hairline top border + one of five rows
/// depending on `vm.state`: quick-import prompt (idle/previewing), confirm (previewReady),
/// an in-flight spinner (confirming), a close button (done), or retry (error).
struct ImportBottomBar: View {
    let vm: ImportViewModel

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            KimaHairline()
            bottomBarContent
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.vertical, KimaSpacing.md)
                .padding(.bottom, KimaSpacing.sm)
        }
        .background(KimaColor.base)
    }

    @ViewBuilder
    private var bottomBarContent: some View {
        switch vm.state {
        case .idle, .previewing:
            quickImportBar
        case .previewReady:
            confirmButton
        case .confirming:
            confirmingIndicator
        case .done:
            closeButton
        case .error:
            retryButton
        }
    }

    private var quickImportBar: some View {
        HStack(spacing: KimaSpacing.md) {
            Spacer(minLength: 0)
            Button { Task { await vm.startQuickImport(using: env.client) } } label: {
                Text("import without preview")
                    .font(KimaType.metaStrong).tracking(0)
                    .foregroundStyle(KimaColor.textMuted)
                    .padding(.horizontal, KimaSpacing.md).frame(height: 36)
                    .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(KimaColor.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(vm.urlText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isBusy)
        }
    }

    private var confirmButton: some View {
        KimaPrimaryButton(title: "import playlist", systemImage: "arrow.down.circle.fill") {
            Task { await vm.confirmImport(using: env.client, canAcquire: env.acquire.canAcquire) }
        }
        .disabled(!vm.canConfirm)
    }

    private var confirmingIndicator: some View {
        KimaPrimaryButton(title: "starting import…", isLoading: true) {}
            .disabled(true)
    }

    private var closeButton: some View {
        KimaPrimaryButton(title: "done") { dismiss() }
    }

    private var retryButton: some View {
        KimaPrimaryButton(title: "try again", style: .secondary) {
            withAnimation { vm.reset() }
        }
    }
}
