import AppKit
import SwiftData
import SwiftUI
import newsprintCore

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Article.fetchedAt, order: .reverse) private var articles: [Article]
    @Query(sort: \Source.title) private var sources: [Source]
    @Query private var settingsItems: [AppSettings]
    @State private var selection: SidebarSelection = .inbox
    @State private var selectedArticle: Article?
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshLoopTask: Task<Void, Never>?
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, sources: sources, articles: articles)
        } content: {
            switch selection {
            case .sources:
                SourcesView(sources: sources, refresh: refresh)
            case .rules:
                RulesView()
            case .settings:
                SettingsView()
            default:
                ArticleListView(
                    articles: filteredArticles,
                    selectedArticle: $selectedArticle
                )
            }
        } detail: {
            ReaderView(article: selectedArticle)
        }
        .task {
            ensureSettingsAndRefreshIfNeeded()
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Articles")
        .focused($searchFocused)
        .onChange(of: selectedArticle?.id) {
            markSelectedReadOnOpenIfNeeded()
        }
        .onChange(of: settingsItems.first?.refreshWhileOpenMinutes) {
            startRefreshLoopIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintRefreshAll)) { _ in
            refreshAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintAddSource)) { _ in
            selection = .sources
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintFocusSearch)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintToggleRead)) { _ in
            saveSelected { $0.isRead.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintToggleStar)) { _ in
            saveSelected { $0.isStarred.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintToggleHidden)) { _ in
            saveSelected { $0.isHidden.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintOpenOriginal)) { _ in
            if let url = selectedArticle?.url {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var filteredArticles: [Article] {
        let filter: ArticleFilter = switch selection {
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
        return ArticleSearchService().filter(articles: articles, filter: filter, searchText: searchText)
    }

    private func ensureSettingsAndRefreshIfNeeded() {
        do {
            let settings = try SettingsRepository.loadOrCreate(in: modelContext)
            if settings.refreshOnLaunch {
                refreshAll()
            } else {
                runRetentionCleanup(settings: settings)
            }
            startRefreshLoopIfNeeded()
        } catch {
            // The UI remains usable even if settings creation fails.
        }
    }

    private func refreshAll() {
        refreshTask?.cancel()
        refreshTask = Task {
            await FeedRefreshService(context: modelContext).refreshAll()
        }
    }

    private func refresh(_ source: Source) {
        refreshTask?.cancel()
        refreshTask = Task {
            await FeedRefreshService(context: modelContext).refresh(source: source)
        }
    }

    private func startRefreshLoopIfNeeded() {
        refreshLoopTask?.cancel()
        guard let minutes = settingsItems.first?.refreshWhileOpenMinutes else {
            return
        }
        refreshLoopTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(minutes * 60))
                if !Task.isCancelled {
                    refreshAll()
                }
            }
        }
    }

    private func runRetentionCleanup(settings: AppSettings) {
        do {
            let result = try RetentionEngine().cleanup(
                context: modelContext,
                retentionDays: settings.retentionDays
            )
            settings.lastRetentionCleanupAt = result.lastCleanupAt
            settings.lastRetentionDeletedCount = result.deletedCount
            try modelContext.save()
        } catch {
            // Retention errors should not block reading.
        }
    }

    private func markSelectedReadOnOpenIfNeeded() {
        guard settingsItems.first?.markReadOnOpen == true, let article = selectedArticle, !article.isRead else {
            return
        }
        saveSelected { $0.isRead = true }
    }

    private func saveSelected(_ change: (Article) -> Void) {
        guard let selectedArticle else { return }
        change(selectedArticle)
        try? modelContext.save()
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
