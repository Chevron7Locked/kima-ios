import CarPlay
import UIKit

// MARK: - Shared list-state helpers
//
// Non-generic on purpose: routing generic fetch/build closures through `Task { @MainActor in }` (`@Sendable`) adds
// Sendable uncertainty. Each screen inlines its own fetch; these only share spinner/empty/loaded plumbing.

/// Show the CarPlay-native loading spinner while a list's first fetch is in flight.
/// `showsSpinnerWhileEmpty` is iOS 18.4+; the deployment target here is 18.0, so this is a
/// graceful no-op on 18.0–18.3 (the list just appears empty until data arrives).
@MainActor
func setCarPlayListLoading(_ template: CPListTemplate) {
    if #available(iOS 18.4, *) { template.showsSpinnerWhileEmpty = true }
}

/// Push a list in its loading state, with the Now Playing button, and return it for the fetch to fill.
@MainActor
func pushLoadingCarPlayList(title: String, on interfaceController: CPInterfaceController) -> CPListTemplate {
    let template = CPListTemplate(title: title, sections: [])
    setCarPlayListLoading(template)
    template.trailingNavigationBarButtons = [nowPlayingBarButton(interfaceController: interfaceController)]
    interfaceController.pushTemplate(template, animated: true) { _, _ in }
    return template
}

/// Show a short empty/error message in place of the spinner. Used both for "loaded but empty"
/// and "the fetch threw" — callers pass copy appropriate to which case it is.
@MainActor
func setCarPlayListEmpty(_ template: CPListTemplate, title: String, subtitle: String) {
    if #available(iOS 18.4, *) { template.showsSpinnerWhileEmpty = false }
    template.emptyViewTitleVariants = [title]
    template.emptyViewSubtitleVariants = [subtitle]
    template.updateSections([])
}

/// The empty state for a list whose fetch threw.
@MainActor
func setCarPlayListLoadFailed(_ template: CPListTemplate) {
    setCarPlayListEmpty(template, title: "couldn't load", subtitle: "check your connection and try again.")
}

/// CarPlay has no toasts: a tap that failed says so in an alert with one "ok" button.
@MainActor
func presentCarPlayError(_ title: String, on interfaceController: CPInterfaceController) {
    let ok = CPAlertAction(title: "ok", style: .cancel) { _ in
        interfaceController.dismissTemplate(animated: true) { _, _ in }
    }
    interfaceController.presentTemplate(CPAlertTemplate(titleVariants: [title], actions: [ok]), animated: true) { _, _ in }
}

/// Apply a loaded, non-empty row list as a single unlabeled section. Multi-section screens call
/// `template.updateSections(_:)` directly. Typed `[CPListTemplateItem]` so cover-shelf screens can mix
/// `CPListImageRowItem` shelves with a trailing `moreNoticeItem`; `[CPListItem]` converts automatically.
@MainActor
func setCarPlayListLoaded(_ template: CPListTemplate, rows: [CPListTemplateItem]) {
    if #available(iOS 18.4, *) { template.showsSpinnerWhileEmpty = false }
    template.updateSections([CPListSection(items: rows)])
}

/// CarPlay caps the number of items a list template may display (`CPListTemplate.maximumItemCount`,
/// varies by head unit). Truncate defensively and leave room for a trailing "+N more" notice —
/// callers check `capped.count < items.count` to decide whether to append one.
@MainActor
func clampedForCarPlay<T>(_ items: [T]) -> [T] {
    let cap = max(1, Int(CPListTemplate.maximumItemCount) - 1)
    return items.count > cap ? Array(items.prefix(cap)) : items
}

/// Trailing, disabled row noting that the list was truncated. Not selectable — just a signpost
/// to browse the rest on the phone, where there's no item-count ceiling.
@MainActor
func moreNoticeItem(remaining: Int) -> CPListItem {
    let item = CPListItem(
        text: remaining == 1 ? "+1 more" : "+\(remaining) more",
        detailText: "see the full list on your phone"
    )
    item.isEnabled = false
    return item
}

/// "Xh Ym" (or bare "Ym" under an hour) for a duration in seconds — used for CONTINUE/Resume
/// time-left labels and book-detail chapter start-time labels. Floors to the minute; negative
/// durations (e.g. a finished book) clamp to "0m" rather than printing a negative value.
func carPlayTimeText(seconds: Double) -> String {
    let totalMinutes = max(0, Int(seconds / 60))
    return totalMinutes >= 60 ? "\(totalMinutes / 60)h \(totalMinutes % 60)m" : "\(totalMinutes)m"
}

/// Trailing nav-bar button that pushes the shared Now Playing template, a quick jump to transport controls. No guard
/// needed: tapped with nothing playing, CarPlay shows its own "Nothing Playing" state. File-scope so every
/// browse/detail template can reuse it.
@MainActor
func nowPlayingBarButton(interfaceController: CPInterfaceController) -> CPBarButton {
    CPBarButton(image: UIImage(systemName: "waveform") ?? UIImage()) { _ in
        pushNowPlaying(on: interfaceController)
    }
}

/// Push the shared Now Playing template, unless it's already on top of the stack. Repeat taps on
/// Resume / Start Over / a chapter row (or the home nav-bar button while already viewing Now
/// Playing) would otherwise stack duplicate instances of the singleton template, which makes
/// "back" behave oddly (popping between two Now Playing screens instead of back to the row list).
@MainActor
func pushNowPlaying(on interfaceController: CPInterfaceController) {
    // Configure the shared template (speed button + "Chapters" up-next for audiobooks, stripped
    // otherwise) BEFORE presenting, so the buttons are present on first paint. Idempotent.
    if let env = CarPlayLink.shared.environment {
        CarPlayNowPlaying.shared.configure(env: env)
    }
    guard interfaceController.topTemplate !== CPNowPlayingTemplate.shared else { return }
    interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true) { _, _ in }
}
