import SwiftData
import SwiftUI
import newsprintCore

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Article.fetchedAt, order: .reverse) private var articles: [Article]
    @Query(sort: \Source.title) private var sources: [Source]
    @State private var selection: SidebarSelection = .inbox
    @State private var selectedArticle: Article?
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, sources: sources, articles: articles)
        } content: {
            switch selection {
            case .sources:
                SourcesView(sources: sources, refresh: refresh)
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
        .onReceive(NotificationCenter.default.publisher(for: .newsprintRefreshAll)) { _ in
            refreshAll()
        }
    }

    private var filteredArticles: [Article] {
        switch selection {
        case .inbox:
            articles.filter { !$0.isHidden }
        case .unread:
            articles.filter { !$0.isRead && !$0.isHidden }
        case .starred:
            articles.filter { $0.isStarred }
        case .hidden:
            articles.filter { $0.isHidden }
        case .source(let id):
            articles.filter { $0.sourceID == id && !$0.isHidden }
        case .sources:
            []
        }
    }

    private func ensureSettingsAndRefreshIfNeeded() {
        do {
            let settings = try SettingsRepository.loadOrCreate(in: modelContext)
            if settings.refreshOnLaunch {
                refreshAll()
            }
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
}

enum SidebarSelection: Hashable {
    case inbox
    case unread
    case starred
    case hidden
    case sources
    case source(UUID)
}

