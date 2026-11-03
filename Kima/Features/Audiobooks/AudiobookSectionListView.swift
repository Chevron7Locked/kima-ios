import SwiftUI

// MARK: - SectionListView (chapters)

/// Chapter list shown when `audiobook.sections.count` is in 1…50: tight numbered rows, tap seeks to
/// `section.start` (book-absolute seconds). The chapter holding the current position is highlighted in `env.accent`.
/// Split out of AudiobookDetailComponents.swift to keep that file under the size cap.
struct SectionListView: View {
    let sections: [AudiobookSection]
    /// 1-based `AudiobookSection.index` of the chapter containing the current playback
    /// position, when this book is the one loaded in the player. Nil hides the highlight
    /// (book not loaded, or not yet resolved).
    var currentIndex: Int? = nil
    /// True when the book is actively playing, vs. loaded-but-paused at `currentIndex`.
    var isPlaying: Bool = false
    let onSelect: (AudiobookSection) -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KimaSectionHeader(title: "chapters")

            ForEach(sections) { section in
                chapterRow(section)
                KimaHairline()
                    .padding(.horizontal, KimaSpacing.lg)
            }
        }
    }

    private func chapterRow(_ section: AudiobookSection) -> some View {
        let isCurrent = section.index == currentIndex
        let tint = isCurrent ? env.accent.color : KimaColor.textMuted

        return Button { onSelect(section) } label: {
            HStack(spacing: KimaSpacing.md) {
                // Index slot — waveform icon when this chapter is actively playing, otherwise
                // the setlist-style number. Only accent-colored when it's the current chapter.
                Group {
                    if isCurrent && isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .medium))
                    } else {
                        Text(String(format: "%02d", section.index))
                            .font(KimaType.caption.monospacedDigit())
                    }
                }
                .foregroundStyle(tint)
                .frame(width: 28, alignment: .leading)

                Text(section.title.lowercased())
                    .font(isCurrent ? KimaType.captionStrong : KimaType.caption)
                    .foregroundStyle(isCurrent ? env.accent.color : KimaColor.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(section.start.durationFormatted)
                    .font(KimaType.caption.monospacedDigit())
                    .foregroundStyle(isCurrent ? env.accent.color.opacity(0.85) : KimaColor.textMuted)
            }
            .padding(.horizontal, KimaSpacing.lg)
            .padding(.vertical, KimaSpacing.md)
            .frame(minHeight: 44)
            .background(isCurrent ? env.accent.color.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
