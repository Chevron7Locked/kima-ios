import SwiftUI
import Observation

// MARK: - ViewModel

/// Manages the initial library scan: POST /api/library/scan → poll
/// GET /api/library/scan/status/:jobId every 2 s until "completed" or "failed".
@MainActor
@Observable
final class SyncProgressViewModel {
    enum Phase: Equatable {
        case starting
        case scanning(jobId: String, progress: Double)
        case completed
        case failed(String)
    }

    let server: KimaServer
    var phase: Phase = .starting
    private var pollTask: Task<Void, Never>?

    init(server: KimaServer) { self.server = server }

    func start() {
        pollTask?.cancel()
        pollTask = Task { await run() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func run() async {
        guard let credential = KimaCredential.fromKeychain(for: server) else {
            phase = .failed("session expired — go back and sign in again.")
            return
        }
        let client = KimaAPIClient(server: server, credential: credential)
        do {
            let scan = try await client.libraryScan()
            phase = .scanning(jobId: scan.jobId, progress: 0)
            await poll(jobId: scan.jobId, using: client)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed("couldn't start the library scan. tap skip; you can scan later from kima's web settings.")
        }
    }

    private func poll(jobId: String, using client: KimaAPIClient) async {
        var ticks = 0
        let maxTicks = 900   // ~30 min at 2s — generous (huge libraries scan slowly), but bounded
        while !Task.isCancelled, ticks < maxTicks {
            do {
                let status = try await client.libraryScanStatus(jobId: jobId)
                switch status.status {
                case "completed":
                    phase = .completed
                    return
                case "failed":
                    phase = .failed("library scan failed. you can scan again from kima's web settings.")
                    return
                default:
                    phase = .scanning(jobId: jobId, progress: status.progress ?? 0)
                }
            } catch {
                // Network blip — keep polling; don't surface transient errors
            }
            ticks += 1
            try? await Task.sleep(for: .seconds(2))
        }
        // Bounded out (not cancelled): non-destructive — the scan keeps running on the server,
        // so tell the user they can continue rather than hard-failing a still-valid scan.
        if !Task.isCancelled {
            phase = .failed("this is taking a while. tap Skip — your library keeps building on the server and will fill in as you use the app.")
        }
    }

    // MARK: - Display helpers

    /// Progress to show: 0 while starting, server value clamped to 90 while scanning
    /// (avoids showing 100 before the server says "completed"), 100 when done.
    var displayProgress: Double {
        switch phase {
        case .starting:                  return 0
        case .scanning(_, let p):        return min(p, 90)
        case .completed:                 return 100
        case .failed:                    return 0
        }
    }

    var statusMessage: String {
        switch phase {
        case .starting:
            return "scanning your library…"
        case .scanning(_, let p):
            if p >= 90 { return "scanning your library…" }
            if p >= 60 { return "scanning your library…" }
            if p >= 30 { return "scanning your library…" }
            if p >  0  { return "scanning your library…" }
            return "scanning your library…"
        case .completed:
            return "done"
        case .failed(let msg):
            return msg
        }
    }

    var completedStepIds: Set<String> {
        switch phase {
        case .completed:
            return ["tracks", "library", "albums", "indexes"]
        case .scanning(_, let p):
            var ids = Set<String>()
            if p >= 15 { ids.insert("tracks") }
            if p >= 30 { ids.insert("library") }
            if p >= 50 { ids.insert("albums") }
            if p >= 70 { ids.insert("indexes") }
            return ids
        default:
            return []
        }
    }

    var isActive: Bool {
        switch phase {
        case .starting, .scanning: return true
        case .completed, .failed:  return false
        }
    }
}

// MARK: - View

/// Post-registration screen: starts the initial library scan, shows determinate progress,
/// and transitions into the app when the scan completes (or lets the user skip).
struct SyncProgressView: View {
    let host: String
    var onComplete: () -> Void
    @State private var vm: SyncProgressViewModel

    init(server: KimaServer, host: String, onComplete: @escaping () -> Void) {
        self.host = host
        self.onComplete = onComplete
        _vm = State(initialValue: SyncProgressViewModel(server: server))
    }

    private let steps: [(id: String, label: String)] = [
        ("tracks",  "scanning tracks"),
        ("library", "building library"),
        ("albums",  "organizing albums"),
        ("indexes", "creating indexes"),
    ]

    var body: some View {
        ZStack {
            AmbientFieldBackdrop(palette: nil).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KimaSpacing.xl) {
                    header
                    progressBar
                    if case let .failed(msg) = vm.phase { KimaErrorCard(message: msg) }
                    stepsGrid
                    Spacer(minLength: KimaSpacing.huge)
                }
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.top, KimaSpacing.xl)
                .kimaReadableWidth(alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .navigationBarBackButtonHidden(true)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: vm.phase) { _, phase in
            guard phase == .completed else { return }
            Task {
                try? await Task.sleep(for: .seconds(1))
                onComplete()
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            Text(vm.phase == .completed ? "done" : "scanning your library")
                .font(KimaType.pageTitle).foregroundStyle(KimaColor.textPrimary).tracking(-0.4)
            Text(vm.isActive
                 ? "scanning your library on \(host). this can take a few minutes."
                 : vm.statusMessage)
                .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if vm.isActive || vm.phase == .completed {
            VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                KimaProgressBar(fraction: vm.displayProgress / 100, height: 4, track: KimaColor.surfaceRaised)
                    .animation(.easeOut(duration: 0.5), value: vm.displayProgress)
                Text(vm.isActive ? "\(Int(vm.displayProgress))% complete" : "complete")
                    .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
            }
        }
    }

    private var stepsGrid: some View {
        let done = vm.completedStepIds
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: KimaSpacing.md
        ) {
            ForEach(steps, id: \.id) { step in
                HStack(spacing: KimaSpacing.sm) {
                    stepBadge(complete: done.contains(step.id))
                    Text(step.label)
                        .font(KimaType.caption)
                        .foregroundStyle(done.contains(step.id) ? KimaColor.textPrimary : KimaColor.textMuted)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(KimaSpacing.lg)
        .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))
    }

    private func stepBadge(complete: Bool) -> some View {
        ZStack {
            Circle()
                .fill(complete ? KimaColor.fillQuiet : KimaColor.surfaceRaised)
                .frame(width: 20, height: 20)
            if complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(KimaColor.textPrimary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("artist info and artwork keep loading in the background.")
                .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: KimaSpacing.sm)
            Button("skip") { onComplete() }
                .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                .kimaHitTarget()
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.vertical, KimaSpacing.sm)
    }
}

#Preview {
    NavigationStack {
        SyncProgressView(
            server: KimaServer(baseURL: URL(string: "https://kima.example.com")!),
            host: "kima.example.com",
            onComplete: {}
        )
    }
}
