import SwiftUI

/// The top of a detail page (album, playlist, imported playlist, audiobook, series, podcast): the cover beside the
/// page's name and its own lines, cleared of the status bar and back button. The hero is as tall as its content.
/// The cover is bigger on regular width.
/// `cover` is the bare art; the hero sizes it, rounds it and gives it the hairline and lift.
struct KimaDetailHero<Cover: View, Info: View>: View {
    let topInset: CGFloat
    @ViewBuilder let cover: () -> Cover
    @ViewBuilder let info: () -> Info

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let side = sizeClass == .regular ? KimaLayout.heroCoverRegular : KimaLayout.heroCover
        HStack(alignment: .top, spacing: KimaSpacing.lg) {
            cover()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: KimaRadius.hero, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KimaRadius.hero, style: .continuous)
                        .strokeBorder(KimaColor.hairline, lineWidth: 1)
                )
                .kimaSleeveElevation(cornerRadius: KimaRadius.hero)

            VStack(alignment: .leading, spacing: KimaSpacing.sm) {
                info()
            }
            Spacer(minLength: 0)
        }
        .kimaHeroPadding(topInset: topInset)
    }
}

/// A detail hero's name: two lines at most, shrinking to fit rather than wrapping word by word.
struct KimaDetailHeroTitle: View {
    let text: String

    var body: some View {
        Text(text.lowercased())
            .font(KimaType.pageTitle)
            .foregroundStyle(KimaColor.textPrimary)
            .tracking(-0.4)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
    }
}

/// The line under a detail hero's name: who made it (artist, author, owner).
struct KimaDetailHeroByline: View {
    let text: String

    var body: some View {
        Text(text.lowercased())
            .font(KimaType.captionStrong)
            .foregroundStyle(KimaColor.textSecondary)
            .lineLimit(2)
    }
}

/// A detail hero's fact line (length, count, year, genre): the parts joined with " · " on one line.
struct KimaDetailHeroMeta: View {
    let parts: [String]

    var body: some View {
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(KimaType.caption)
                .monospacedDigit()
                .foregroundStyle(KimaColor.textMuted)
                .lineLimit(1)
        }
    }
}
