import SwiftUI

// MARK: - Server

struct ServerSection: View {
    let host: String
    let scheme: String?
    let connectionState: SettingsViewModel.ConnectionState
    let onTestConnection: () -> Void
    let onChangeServer: () -> Void

    @State private var confirmingChange = false

    var body: some View {
        KimaSectionHeader(title: "server")

        VStack(alignment: .leading, spacing: 0) {
            // Host URL + security badge
            VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                Text("connected to")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                Text(host)
                    .font(KimaType.headline)
                    .foregroundStyle(KimaColor.textPrimary)
                ConnectionSecurityBadge(scheme: scheme, host: host)
            }
            .padding(.vertical, KimaSpacing.lg)

            KimaHairline()

            // Test connection — spinner while .testing; ok/failed state displayed inline.
            Button(action: onTestConnection) {
                HStack {
                    Image(systemName: connectionIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(connectionColor)
                        .frame(width: 20)
                    Text(connectionLabel)
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textSecondary)
                    Spacer(minLength: 0)
                    if connectionState == .testing {
                        ProgressView().tint(KimaColor.textMuted).scaleEffect(0.8)
                    }
                }
                .padding(.vertical, KimaSpacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(connectionState == .testing)

            KimaHairline()

            // Change server — asks first; keeps the account and opens the address screen.
            Button { confirmingChange = true } label: {
                HStack {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KimaColor.textSecondary)
                        .frame(width: 20)
                    Text("change server")
                        .font(KimaType.body)
                        .foregroundStyle(KimaColor.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KimaColor.textMuted)
                }
                .padding(.vertical, KimaSpacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .confirmationDialog("change server?", isPresented: $confirmingChange, titleVisibility: .visible) {
                Button("change server", action: onChangeServer)
                Button("cancel", role: .cancel) {}
            } message: {
                Text("stops playback and opens the server address screen.")
            }
        }
        .padding(.horizontal, KimaSpacing.lg)
    }

    private var connectionIcon: String {
        switch connectionState {
        case .idle, .testing: return "network"
        case .ok:             return "checkmark.circle"
        case .failed:         return "exclamationmark.triangle"
        }
    }

    private var connectionColor: Color {
        switch connectionState {
        case .ok:     return KimaColor.positive
        case .failed: return .red
        default:      return KimaColor.textSecondary
        }
    }

    private var connectionLabel: String {
        switch connectionState {
        case .idle:    return "test connection"
        case .testing: return "testing…"
        case .ok:      return "connected"
        case .failed:  return "can't reach server"
        }
    }
}
