import AppKit
import SwiftData
import SwiftUI
import newsprintCore

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var agentController: NewsprintAgentController
    @Query private var settingsItems: [AppSettings]
    @StateObject private var viewModel = RootViewModel()
    @StateObject private var feedStore = ArticleFeedStore()
    @State private var selection: SidebarSelection = .inbox
    @State private var expandedArticleID: String?
    @State private var focusedArticleID: String?
    @State private var previewArticleID: String?
    @State private var searchText = ""
    @State private var feedSort: ArticleFeedSort = .hot
    @State private var hasOpenedSources = false
    @State private var hasOpenedRules = false
    @State private var hasOpenedSettings = false
    @AppStorage("newsprint.previewMode") private var previewModeRawValue = PreviewMode.reader.rawValue
    @AppStorage("newsprint.previewPaneCollapsed") private var isPreviewCollapsed = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let base = AnyView(rootLayout)
        return configuredRootLayout(base)
    }

    private var rootLayout: some View {
        PersistentTwoPaneSplitView {
            NavigationStack {
                SidebarView(selection: $selection, sources: viewModel.sources, tagNames: feedStore.tagNames)
            }
            .background(theme.paneBackground)
        } content: {
            NavigationStack {
                contentPane
            }
            .background(theme.paneBackground)
        }
    }

    private func configuredRootLayout(_ base: AnyView) -> AnyView {
        var view = AnyView(base.task {
            await bootstrapDashboard()
        })

        view = AnyView(view.modifier(RootAppearanceModifier(
            theme: theme,
            readerFontChoice: readerFontChoice,
            readerFontSize: readerFontSize,
            articleListDensity: articleListDensity,
            webPreviewHorizontalPadding: webPreviewHorizontalPadding
        )))

        view = AnyView(view.overlay(alignment: .bottom) {
            errorOverlay
        })

        view = AnyView(view.onChange(of: expandedArticleID) {
            markExpandedReadOnOpenIfNeeded()
        })

        view = AnyView(view.onChange(of: settingsItems.first?.refreshWhileOpenMinutes) {
            agentController.updateRefreshInterval(minutes: settingsItems.first?.refreshWhileOpenMinutes)
        })

        view = AnyView(view.onChange(of: selection) {
            markManagementPaneOpened(selection)
            if selection.isArticleFeedSelection {
                expandedArticleID = nil
                focusedArticleID = nil
                reloadFeed()
            }
        })

        view = AnyView(view.onChange(of: searchText) {
            expandedArticleID = nil
            if selection.isArticleFeedSelection {
                reloadFeed()
            }
        })

        view = AnyView(view.onChange(of: feedSort) {
            expandedArticleID = nil
            if selection.isArticleFeedSelection {
                reloadFeed()
            }
        })

        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .newsprintDataChanged)) { notification in
            viewModel.reloadSources(context: modelContext)
            handleDataChanged(notification.object)
        })

        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .newsprintRefreshAll)) { _ in
            agentController.refreshAll()
        })

        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .newsprintAddSource)) { _ in
            selection = .sources
        })

        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .newsprintFocusSearch)) { _ in
            searchFocused = true
        })

        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .newsprintToggleRead)) { _ in
            saveSelected(.toggleRead)
        })

        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .newsprintToggleStar)) { _ in
            saveSelected(.toggleStar)
        })

        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .newsprintToggleHidden)) { _ in
            saveSelected(.toggleHidden)
        })

        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .newsprintOpenOriginal)) { _ in
            if let url = actionArticle?.url {
                NSWorkspace.shared.open(url)
            }
        })

        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .newsprintTogglePreviewPane)) { _ in
            isPreviewCollapsed.toggle()
            if !isPreviewCollapsed, previewArticleID == nil {
                previewArticleID = actionArticle?.id
            }
        })

        return view
    }

    private struct RootAppearanceModifier: ViewModifier {
        let theme: NewsprintTheme
        let readerFontChoice: ReaderFontChoice
        let readerFontSize: Int
        let articleListDensity: ArticleListDensity
        let webPreviewHorizontalPadding: Int

        func body(content: Content) -> some View {
            content
                .environment(\.newsprintTheme, theme)
                .environment(\.readerFontChoice, readerFontChoice)
                .environment(\.readerFontSize, readerFontSize)
                .environment(\.articleListDensity, articleListDensity)
                .environment(\.webPreviewHorizontalPadding, webPreviewHorizontalPadding)
                .preferredColorScheme(theme.colorScheme)
                .tint(theme.tint)
                .background(theme.windowBackground)
        }
    }

    @ViewBuilder
    private var errorOverlay: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.red.opacity(0.9), in: Capsule())
                .padding(.bottom, 10)
        }
    }

    private func bootstrapDashboard() async {
        viewModel.bootstrap(
            context: modelContext,
            settings: settingsItems.first,
            onDataChanged: { reloadFeedAfterBulkChange() }
        )
        reloadFeed()
        NewsprintLog.startup.info("Tag load scheduled after 1.0s")
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        feedStore.refreshTagNames(context: modelContext)
    }

    @ViewBuilder
    private var contentPane: some View {
        ZStack {
            ArticleFeedView(
                displayItems: feedStore.renderItems,
                counts: feedStore.counts,
                sources: viewModel.sources,
                pendingRefreshSummary: feedStore.pendingRefreshSummary,
                selection: $selection,
                searchText: $searchText,
                feedSort: $feedSort,
                searchFocused: $searchFocused,
                expandedArticleID: $expandedArticleID,
                focusedArticleID: $focusedArticleID,
                isLoading: feedStore.isLoading,
                isPreparingFeed: feedStore.isPreparingFeed,
                isRefreshing: agentController.isRefreshing || feedStore.isPreparingFeed,
                hasLoadedInitialPage: feedStore.hasLoadedInitialPage,
                previewArticle: previewArticle,
                previewArticleID: $previewArticleID,
                previewMode: previewModeBinding,
                isPreviewCollapsed: $isPreviewCollapsed,
                reloadGeneration: feedStore.bulkReloadGeneration,
                edgeResetGeneration: feedStore.edgeResetGeneration,
                onNearEnd: { index in
                    feedStore.shiftRenderWindowIfNeeded(localIndex: index, context: modelContext)
                },
                cleanHome: cleanHome,
                applyPendingRefresh: applyPendingRefresh,
                dismissPendingRefresh: {
                    feedStore.dismissPendingRefresh()
                },
                onArticleAction: saveArticle
            )
            .opacity(selection.isArticleFeedSelection ? 1 : 0)
            .allowsHitTesting(selection.isArticleFeedSelection)

            managementPane
                .opacity(selection.isArticleFeedSelection ? 0 : 1)
                .allowsHitTesting(!selection.isArticleFeedSelection)
        }
    }

    @ViewBuilder
    private var managementPane: some View {
        ZStack {
            if hasOpenedSources || selection == .sources {
                sourcesPane
                    .opacity(selection == .sources ? 1 : 0)
                    .allowsHitTesting(selection == .sources)
            }

            if hasOpenedRules || selection == .rules {
                RulesView()
                    .opacity(selection == .rules ? 1 : 0)
                    .allowsHitTesting(selection == .rules)
            }

            if hasOpenedSettings || selection == .settings {
                SettingsView()
                    .opacity(selection == .settings ? 1 : 0)
                    .allowsHitTesting(selection == .settings)
            }
        }
    }

    private var sourcesPane: some View {
        SourcesView(
            sources: viewModel.sources,
            refresh: { source in
                agentController.refresh(sourceID: source.id)
            },
            sourceChanged: {
                viewModel.reloadSources(context: modelContext)
            },
            sourceContentChanged: {
                reloadFeedAfterBulkChange()
            }
        )
    }

    private func markManagementPaneOpened(_ selection: SidebarSelection) {
        switch selection {
        case .sources:
            hasOpenedSources = true
        case .rules:
            hasOpenedRules = true
        case .settings:
            hasOpenedSettings = true
        case .inbox, .unread, .today, .starred, .hidden, .source, .tag:
            break
        }
    }

    private var theme: NewsprintTheme {
        NewsprintTheme.make(settingsItems.first?.themeChoice ?? .system)
    }

    private var readerFontChoice: ReaderFontChoice {
        settingsItems.first?.readerFontChoice ?? .system
    }

    private var readerFontSize: Int {
        settingsItems.first?.readerFontSize ?? 17
    }

    private var articleListDensity: ArticleListDensity {
        settingsItems.first?.articleListDensity ?? .comfortable
    }

    private var webPreviewHorizontalPadding: Int {
        settingsItems.first?.webPreviewHorizontalPadding ?? 8
    }

    private var activeFilter: ArticleFilter {
        switch selection {
        case .inbox:
            .inbox
        case .unread:
            .unread
        case .today:
            .today
        case .starred:
            .starred
        case .hidden:
            .hidden
        case .source(let id):
            .source(id)
        case .tag(let tag):
            .tag(tag)
        case .sources, .rules, .settings:
            .inbox
        }
    }

    private var previewModeBinding: Binding<PreviewMode> {
        Binding {
            PreviewMode(storedRawValue: previewModeRawValue)
        } set: { mode in
            previewModeRawValue = mode.rawValue
        }
    }

    private var previewArticle: Article? {
        guard let previewArticleID else { return nil }
        return feedStore.articles.first { $0.id == previewArticleID }
    }

    private var actionArticle: Article? {
        let id = expandedArticleID ?? focusedArticleID
        guard let id else { return nil }
        return feedStore.articles.first { $0.id == id }
    }

    private func markExpandedReadOnOpenIfNeeded() {
        guard settingsItems.first?.markReadOnOpen == true,
              let expandedArticleID,
              let article = feedStore.articles.first(where: { $0.id == expandedArticleID }),
              !article.isRead else {
            return
        }
        saveArticle(article, .markRead)
    }

    private func saveSelected(_ mutation: ArticleStateMutation) {
        guard let article = actionArticle else { return }
        saveArticle(article, mutation)
    }

    private func saveArticle(_ article: Article, _ mutation: ArticleStateMutation) {
        let previousState = ArticleStateSnapshot(article: article)
        guard viewModel.saveArticleState(article, mutation: mutation, context: modelContext) else {
            return
        }
        feedStore.refreshAfterArticleMutation(
            context: modelContext,
            article: article,
            previousState: previousState,
            mutation: mutation
        )
    }

    private func reloadFeed() {
        feedStore.reloadIfNeeded(context: modelContext, filter: activeFilter, searchText: searchText, sort: feedSort)
    }

    private func reloadFeedAfterBulkChange() {
        feedStore.reloadAfterBulkDataChange(context: modelContext)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            feedStore.refreshTagNames(context: modelContext)
        }
    }

    private func handleDataChanged(_ object: Any?) {
        if let event = object as? FeedRefreshEvent {
            if FeedRefreshApplicationPolicy.shouldDefer(
                origin: event.origin,
                isArticleFeedVisible: selection.isArticleFeedSelection
            ), event.summary.hasFeedChanges {
                feedStore.storePendingRefresh(event.summary)
                scheduleTagRefresh()
            } else {
                applyRefreshSummary(event.summary)
            }
            return
        }

        if let summary = object as? FeedRefreshSummary {
            applyRefreshSummary(summary)
            return
        }

        if let summary = object as? SourceRefreshSummary {
            feedStore.beginPreparingFeed()
            Task { @MainActor in
                await Task.yield()
                feedStore.prepareAfterSourceRefresh(context: modelContext, summary: summary)
                scheduleTagRefresh()
            }
            return
        }

        feedStore.beginPreparingFeed()
        Task { @MainActor in
            await Task.yield()
            reloadFeedAfterBulkChange()
            feedStore.finishPreparingFeed()
        }
    }

    private func applyRefreshSummary(_ summary: FeedRefreshSummary) {
        feedStore.beginPreparingFeed()
        Task { @MainActor in
            await Task.yield()
            feedStore.prepareAfterRefresh(context: modelContext, summary: summary)
            scheduleTagRefresh()
        }
    }

    private func applyPendingRefresh() {
        feedStore.beginPreparingFeed()
        Task { @MainActor in
            await Task.yield()
            feedStore.applyPendingRefresh(context: modelContext)
            scheduleTagRefresh()
        }
    }

    private func scheduleTagRefresh() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            feedStore.refreshTagNames(context: modelContext)
        }
    }

    private func cleanHome() {
        do {
            _ = try feedStore.cleanHome(context: modelContext)
            expandedArticleID = nil
            focusedArticleID = nil
            if let previewArticleID,
               !feedStore.articles.contains(where: { $0.id == previewArticleID }) {
                self.previewArticleID = nil
            }
            viewModel.errorMessage = nil
            scheduleTagRefresh()
        } catch {
            viewModel.errorMessage = "Could not clean home: \(error.localizedDescription)"
        }
    }
}

enum SidebarSelection: Hashable {
    case inbox
    case unread
    case today
    case starred
    case hidden
    case sources
    case rules
    case settings
    case source(UUID)
    case tag(String)
}

private extension SidebarSelection {
    var isArticleFeedSelection: Bool {
        switch self {
        case .inbox, .unread, .today, .starred, .hidden, .source, .tag:
            true
        case .sources, .rules, .settings:
            false
        }
    }
}
