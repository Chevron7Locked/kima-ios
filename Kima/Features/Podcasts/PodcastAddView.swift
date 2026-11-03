import SwiftUI

// MARK: - PodcastAddView

/// Sheet: search-to-subscribe as the primary path; RSS URL entry as a secondary fallback.
///
/// Calls `onSubscribed(newPodcastId)` on success — the parent is responsible for
/// navigating to the detail view and reloading its subscription list.
struct PodcastAddView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ToastCenter.self)   private var toastCenter
    @Environment(\.dismiss)          private var dismiss

    let onSubscribed: (String) -> Void

    // Search
    @State private var searchQuery   = ""
    @State private var searchResults: [DiscoverPodcastResult] = []
    @State private var isSearching   = false
    @State private var searchError:  String? = nil
    @State private var searchTask:   Task<Void, Never>? = nil

    // Subscribe-from-result
    @State private var subscribingId: String? = nil

    // RSS fallback
    @State private var rssUrl           = ""
    @State private var isSubscribingRSS = false

    // Return closes the keyboard on both fields.
    private enum Field: Hashable { case search, rss }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ZStack {
                KimaScreenGround()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        searchSection
                        rssSection
                        Spacer(minLength: KimaSpacing.huge)
                    }
                }
                .kimaKeyboardSafeCanvas()
            }
            .navigationTitle("add podcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("cancel") { dismiss() }
                        .foregroundStyle(KimaColor.textMuted)
                }
            }
        }
        .onChange(of: searchQuery) { _, new in scheduleSearch(query: new) }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: - Search section

    @ViewBuilder
    private var searchSection: some View {
        KimaSectionHeader(title: "search")

        VStack(alignment: .leading, spacing: KimaSpacing.md) {
            KimaSearchField(prompt: "podcast name or topic…", isBusy: isSearching,
                            text: $searchQuery,
                            isFocused: Binding(
                                get: { focusedField == .search },
                                set: { focusedField = $0 ? .search : nil }))
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.bottom, KimaSpacing.md)

        // Results / states
        if let err = searchError {
            Text(err)
                .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.bottom, KimaSpacing.md)
        } else if searchQuery.count >= 2 && !isSearching && searchResults.isEmpty {
            Text("no results for \"\(searchQuery)\"")
                .font(KimaType.caption).foregroundStyle(KimaColor.textMuted)
                .padding(.horizontal, KimaSpacing.lg)
                .padding(.bottom, KimaSpacing.md)
        } else {
            ForEach(searchResults) { result in
                DiscoverPodcastRow(
                    result: result,
                    isSubscribing: subscribingId == result.id,
                    anySubscribing: subscribingId != nil
                ) {
                    subscribeResult(result)
                }
            }
        }
    }

    // MARK: - RSS fallback section

    @ViewBuilder
    private var rssSection: some View {
        KimaSectionHeader(title: "subscribe via RSS")

        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            HStack(spacing: KimaSpacing.sm) {
                TextField("https://feeds.example.com/podcast.rss", text: $rssUrl)
                    .font(KimaType.body)
                    .foregroundStyle(KimaColor.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .focused($focusedField, equals: .rss)
                    .submitLabel(.go)
                    .onSubmit {
                        focusedField = nil
                        if !rssUrl.trimmingCharacters(in: .whitespaces).isEmpty, !isSubscribingRSS {
                            subscribeRSS()
                        }
                    }
                    .padding(KimaSpacing.md)
                    .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))

                KimaPrimaryButton(title: "add", isLoading: isSubscribingRSS, size: .compact, action: subscribeRSS)
                    .disabled(rssUrl.trimmingCharacters(in: .whitespaces).isEmpty || isSubscribingRSS)
            }

            Text("the RSS feed link is usually on the podcast's website.")
                .font(KimaType.meta).foregroundStyle(KimaColor.textMuted)
        }
        .padding(.horizontal, KimaSpacing.lg)
    }

    // MARK: - Search logic

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        guard query.count >= 2 else {
            searchResults = []
            searchError = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            isSearching = true
            searchError = nil
            do {
                let results = try await env.client.searchDiscover(query: query, type: "podcasts")
                guard !Task.isCancelled else { return }
                searchResults = results
            } catch {
                guard !Task.isCancelled else { return }
                searchError = "search failed. check your connection."
                searchResults = []
            }
            isSearching = false
        }
    }

    // MARK: - Subscribe logic

    private func subscribeResult(_ result: DiscoverPodcastResult) {
        guard let feedUrl = result.feedUrl, subscribingId == nil else { return }
        subscribingId = result.id
        Task {
            defer { subscribingId = nil }
            await subscribe(feedUrl: feedUrl, itunesId: result.itunesIdString, failureMessage: "couldn't subscribe")
        }
    }

    private func subscribeRSS() {
        let url = rssUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !isSubscribingRSS else { return }
        isSubscribingRSS = true
        Task {
            defer { isSubscribingRSS = false }
            await subscribe(feedUrl: url, itunesId: nil, failureMessage: "couldn't subscribe. check the RSS link.")
        }
    }

    /// Subscribes, then closes the sheet and reports the new podcast; `failureMessage` is the toast when the request throws.
    private func subscribe(feedUrl: String, itunesId: String?, failureMessage: String) async {
        do {
            let response = try await env.client.subscribePodcast(feedUrl: feedUrl, itunesId: itunesId)
            if response.success, let id = response.podcast?.id {
                toastCenter.show("subscribed", style: .success)
                dismiss()
                onSubscribed(id)
            } else {
                toastCenter.show(response.message ?? "couldn't subscribe", style: .error)
            }
        } catch {
            toastCenter.show(failureMessage, style: .error)
        }
    }
}
