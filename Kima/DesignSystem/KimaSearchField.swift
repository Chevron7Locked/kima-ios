import SwiftUI

/// The app's one search field. Four dismiss paths (Return/submit, inline Done, clear, and the host's keyboard-safe
/// canvas) so a keyboard can never get stranded. `@FocusState` lives inside this view so focus churn re-renders only it.
/// Hosts bind `text` to their search string; `onSubmit` fires before the keyboard dismisses. `leading` takes the
/// magnifying glass's place, for a control that belongs to the field (the vibe map blend's "more ▾").
struct KimaSearchField<Leading: View>: View {
    var prompt: String = "search"
    var submitLabel: SubmitLabel = .search
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never
    /// Shows a spinner in place of the clear button while a search runs.
    var isBusy = false
    var onSubmit: (() -> Void)? = nil

    @Binding var text: String
    /// Optional mirror of the field's focus, for hosts that dismiss the keyboard themselves.
    var isFocused: Binding<Bool>? = nil
    @ViewBuilder var leading: () -> Leading
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: KimaSpacing.sm) {
            if Leading.self == EmptyView.self {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KimaColor.textMuted)
            } else {
                leading()
            }

            TextField("", text: $text, prompt: .kimaPrompt(prompt))
                .font(KimaType.body)
                .foregroundStyle(KimaColor.textPrimary)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(submitLabel)
                .onSubmit {
                    onSubmit?()
                    focused = false
                }

            if isBusy {
                ProgressView().tint(KimaColor.textMuted).scaleEffect(0.8)
            } else if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(KimaColor.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("clear search")
            }

            // Explicit escape hatch — resigns focus while keeping the query.
            if focused {
                Button("done") { focused = false }
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textSecondary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("dismiss keyboard")
            }
        }
        .padding(.horizontal, KimaSpacing.md)
        .frame(height: KimaLayout.minTouchTarget)
        .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KimaRadius.card, style: .continuous)
                .strokeBorder(focused ? KimaColor.hairlineStrong : KimaColor.hairline, lineWidth: 1)
        )
        .onChange(of: focused) { _, f in if isFocused?.wrappedValue != f { isFocused?.wrappedValue = f } }
        .onChange(of: isFocused?.wrappedValue ?? false) { _, f in if focused != f { focused = f } }
        .onAppear { if isFocused?.wrappedValue == true { focused = true } }
    }
}

extension KimaSearchField where Leading == EmptyView {
    /// The plain field, with the magnifying glass at its start.
    init(prompt: String = "search", submitLabel: SubmitLabel = .search, keyboardType: UIKeyboardType = .default,
         autocapitalization: TextInputAutocapitalization = .never, isBusy: Bool = false,
         onSubmit: (() -> Void)? = nil, text: Binding<String>, isFocused: Binding<Bool>? = nil) {
        self.init(prompt: prompt, submitLabel: submitLabel, keyboardType: keyboardType,
                  autocapitalization: autocapitalization, isBusy: isBusy, onSubmit: onSubmit,
                  text: text, isFocused: isFocused, leading: { EmptyView() })
    }
}

// MARK: - Tap-outside dismiss

/// Put ONE of these behind the scrollable content of any screen that hosts a text input:
/// a tap anywhere on the empty canvas resigns the keyboard. Combined with each screen's
/// `.scrollDismissesKeyboard(.interactively)` this makes dead keyboards structurally impossible.
struct KimaKeyboardTapCatcher: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil)
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Keyboard-safe canvas wrapper: scroll-to-dismiss + tap-catcher background. Apply on the ScrollView/ZStack of every
    /// screen that contains a KimaSearchField or TextField. `.immediately` (not `.interactively`) so a swipe resigns the
    /// keyboard outright; it is deterministic under automation, where the interactive variant flaked.
    func kimaKeyboardSafeCanvas() -> some View {
        self
            .scrollDismissesKeyboard(.immediately)
            .background(KimaKeyboardTapCatcher())
    }
}
