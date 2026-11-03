import SwiftUI

// MARK: - Downloads

struct DownloadsSection: View {
    let storageUsed: String?
    let isClearingCache: Bool
    let onClearCache: () -> Void

    var body: some View {
        KimaSectionHeader(title: "downloads")

        VStack(alignment: .leading, spacing: 0) {
            // Navigate to Lidarr job list
            SettingsNavRow(destination: { ActiveDownloadsView() }) {
                Label("active downloads", systemImage: "arrow.down.circle")
            }

            KimaHairline()

            // Size of what "clear image cache" removes (cover images in memory + URL cache)
            HStack {
                Text("image cache")
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                Spacer(minLength: 0)
                Text(storageUsed ?? "calculating…")
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
            }
            .padding(.vertical, KimaSpacing.lg)

            KimaHairline()

            // Clear image cache (NSCache in-memory + URLCache system cache)
            Button(action: onClearCache) {
                HStack {
                    Label(
                        isClearingCache ? "clearing…" : "clear image cache",
                        systemImage: "trash"
                    )
                    .font(KimaType.body)
                    .foregroundStyle(isClearingCache ? KimaColor.textMuted : KimaColor.textPrimary)
                    Spacer(minLength: 0)
                    if isClearingCache {
                        ProgressView().tint(KimaColor.textMuted).scaleEffect(0.8)
                    }
                }
                .padding(.vertical, KimaSpacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isClearingCache)
        }
        .padding(.horizontal, KimaSpacing.lg)
    }
}
