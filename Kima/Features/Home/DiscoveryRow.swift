import SwiftUI

// MARK: - DiscoveryRow

/// Home-screen entry point for Discover Weekly + Releases Radar — a compact two-up
/// "discovery row" sitting beneath the Vibe Map hero.
///
/// Two equal top-lit tiles (no side stripe): icon badge, Bricolage title, one-line descriptor, chevron.
struct DiscoveryRow: View {
    let onDiscoverTap: () -> Void
    let onReleasesTap: () -> Void

    var body: some View {
        HStack(spacing: KimaSpacing.md) {
            DiscoveryChip(
                icon: "safari",
                title: "discover weekly",
                descriptor: "new albums every week",
                onTap: onDiscoverTap
            )
            DiscoveryChip(
                icon: "waveform.badge.plus",
                title: "new releases",
                descriptor: "new from your artists",
                onTap: onReleasesTap
            )
        }
        .padding(.horizontal, KimaSpacing.lg)
        // Headerless section: the standard between-section gap above it.
        .padding(.top, KimaSpacing.xxl)
    }
}

// MARK: - DiscoveryChip

/// A single editorial feature-entry tile. No colored side border — hierarchy comes from
/// the icon badge, the hairline frame, and the accent-tinted trailing affordance only.
private struct DiscoveryChip: View {
    let icon: String
    let title: String
    let descriptor: String
    let onTap: () -> Void


    var body: some View {
        Button(action: onTap) {
            HStack(spacing: KimaSpacing.sm) {
                ZStack {
                    Circle().fill(KimaColor.fillQuiet)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KimaColor.textPrimary)
                }
                .frame(width: 30, height: 30)

                // Title + descriptor — ONE line each (no forced \n line break, no 148pt slab).
                VStack(alignment: .leading, spacing: KimaSpacing.xs) {
                    Text(title.lowercased())
                        .font(KimaType.bodyStrong)
                        .foregroundStyle(KimaColor.textPrimary)
                        .tracking(-0.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(descriptor)
                        .font(KimaType.meta)
                        .foregroundStyle(KimaColor.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: KimaSpacing.xs)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KimaColor.textMuted)
            }
            .padding(.horizontal, KimaSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 62)
            // Top-lit physical face (shared with the radio tiles) + the shared sleeve elevation —
            // a solid object floating on the lit ground, not a flat fill.
            .background(LinearGradient.kimaPlate, in: RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous))
            .kimaSleeveElevation(cornerRadius: KimaRadius.card)
        }
        .buttonStyle(.kimaCard)
    }
}
