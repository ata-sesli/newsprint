import AppKit
import SwiftData
import SwiftUI
import newsprintCore

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Article.fetchedAt, order: .reverse) private var articles: [Article]
    @Query private var settingsItems: [AppSettings]
    @StateObject private var viewModel = RootViewModel()
    @State private var selection: SidebarSelection = .inbox
    @State private var expandedArticleID: String?
    @State private var focusedArticleID: String?
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        PersistentTwoPaneSplitView {
            NavigationStack {
                SidebarView(selection: $selection, sources: viewModel.sources, articles: articles)
            }
            .background(theme.paneBackground)
        } content: {
            NavigationStack {
                contentPane
            }
            .background(theme.paneBackground)
        }
        .task {
            viewModel.bootstrap(context: modelContext, settings: settingsItems.first)
        }
        .environment(\.newsprintTheme, theme)
        .environment(\.readerFontChoice, readerFontChoice)
        .environment(\.readerFontSize, readerFontSize)
        .environment(\.articleListDensity, articleListDensity)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.tint)
        .background(theme.windowBackground)
        .overlay(alignment: .bottom) {
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
        .onChange(of: expandedArticleID) {
            markExpandedReadOnOpenIfNeeded()
        }
        .onChange(of: settingsItems.first?.refreshWhileOpenMinutes) {
            viewModel.startRefreshLoop(
                context: modelContext,
                minutes: settingsItems.first?.refreshWhileOpenMinutes
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintRefreshAll)) { _ in
            viewModel.refreshAll(context: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintAddSource)) { _ in
            selection = .sources
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintFocusSearch)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintToggleRead)) { _ in
            saveSelected(.toggleRead)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintToggleStar)) { _ in
            saveSelected(.toggleStar)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintToggleHidden)) { _ in
            saveSelected(.toggleHidden)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsprintOpenOriginal)) { _ in
            if let url = actionArticle?.url {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @ViewBuilder
    private var contentPane: some View {
        switch selection {
        case .sources:
            SourcesView(
                sources: viewModel.sources,
                refresh: { source in viewModel.refresh(source, context: modelContext) },
                sourceChanged: { viewModel.reloadSources(context: modelContext) }
            )
        case .rules:
            RulesView()
        case .settings:
            SettingsView()
        default:
            ArticleFeedView(
                articles: filteredArticles,
                allArticles: articles,
                sources: viewModel.sources,
                selection: $selection,
                searchText: $searchText,
                searchFocused: $searchFocused,
                expandedArticleID: $expandedArticleID,
                focusedArticleID: $focusedArticleID,
                onArticleAction: saveArticle
            )
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

    private var actionArticle: Article? {
        let id = expandedArticleID ?? focusedArticleID
        guard let id else { return nil }
        return articles.first { $0.id == id }
    }

    private func markExpandedReadOnOpenIfNeeded() {
        guard settingsItems.first?.markReadOnOpen == true,
              let expandedArticleID,
              let article = articles.first(where: { $0.id == expandedArticleID }),
              !article.isRead else {
            return
        }
        viewModel.saveArticleState(article, mutation: .markRead, context: modelContext)
    }

    private func saveSelected(_ mutation: ArticleStateMutation) {
        guard let article = actionArticle else { return }
        saveArticle(article, mutation)
    }

    private func saveArticle(_ article: Article, _ mutation: ArticleStateMutation) {
        viewModel.saveArticleState(article, mutation: mutation, context: modelContext)
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
