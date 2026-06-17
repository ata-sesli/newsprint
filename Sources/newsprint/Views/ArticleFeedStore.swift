import Foundation
import SwiftData
import newsprintCore

@MainActor
final class ArticleFeedStore: ObservableObject {
    static let pageSize = 750
    static let loadMoreThreshold = 50

    @Published private(set) var articles: [Article] = []
    @Published private(set) var renderItems: [ArticleFeedDisplayItem] = []
    @Published private(set) var counts = FeedCounts()
    @Published private(set) var tagNames: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPreparingFeed = false
    @Published private(set) var pendingRefreshSummary: FeedRefreshSummary?
    @Published private(set) var hasLoadedInitialPage = false
    @Published private(set) var hasMore = true
    @Published private(set) var offset = 0
    @Published private(set) var bulkReloadGeneration = 0
    @Published private(set) var edgeResetGeneration = 0

    private var currentFilter: ArticleFilter = .inbox
    private var currentSearchText = ""
    private var currentSort: ArticleFeedSort = .hot
    private var displayItems: [ArticleFeedDisplayItem] = []
    private var renderWindow = ArticleRenderWindow()
    private var loadGeneration = 0
    private var hasLoadedPage = false

    func reloadIfNeeded(context: ModelContext, filter: ArticleFilter, searchText: String, sort: ArticleFeedSort) {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hasLoadedPage ||
              articles.isEmpty ||
              currentFilter != filter ||
              currentSearchText != normalizedSearchText ||
              currentSort != sort else {
            return
        }

        reload(context: context, filter: filter, searchText: normalizedSearchText, sort: sort)
    }

    func reload(context: ModelContext, filter: ArticleFilter, searchText: String, sort: ArticleFeedSort? = nil) {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedSort = sort ?? currentSort
        currentFilter = filter
        currentSearchText = normalizedSearchText
        currentSort = selectedSort
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        if articles.isEmpty {
            hasLoadedInitialPage = false
        }

        do {
            let timing = StartupTimingRecorder()
            let repository = SwiftDataArticleFeedRepository(context: context)
            let page = try repository.fetchPage(
                filter: filter,
                searchText: normalizedSearchText,
                offset: 0,
                limit: Self.pageSize,
                sort: selectedSort
            )
            timing.markAndLog("First feed page fetch")
            guard generation == loadGeneration else { return }
            articles = page
            rebuildDisplayItems(resetWindow: true)
            offset = page.count
            hasMore = page.count == Self.pageSize
            counts = try repository.fetchCounts()
            timing.markAndLog("Count fetch")
            hasLoadedPage = true
            hasLoadedInitialPage = true
            bulkReloadGeneration += 1
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            articles = []
            rebuildDisplayItems(resetWindow: true)
            offset = 0
            hasMore = false
            hasLoadedPage = true
            hasLoadedInitialPage = true
            isLoading = false
        }
    }

    func loadMoreIfNeeded(currentIndex: Int, context: ModelContext) {
        guard hasMore,
              !isLoading,
              currentIndex >= max(0, articles.count - Self.loadMoreThreshold) else {
            return
        }

        isLoading = true
        do {
            let timing = StartupTimingRecorder()
            let repository = SwiftDataArticleFeedRepository(context: context)
            let nextPage = try repository.fetchPage(
                filter: currentFilter,
                searchText: currentSearchText,
                offset: offset,
                limit: Self.pageSize,
                sort: currentSort
            )
            timing.markAndLog("Additional feed page fetch")
            articles.append(contentsOf: nextPage)
            appendDisplayItems(for: nextPage)
            offset += nextPage.count
            hasMore = nextPage.count == Self.pageSize
            counts = try repository.fetchCounts()
            isLoading = false
        } catch {
            hasMore = false
            isLoading = false
        }
    }

    func refreshAfterArticleMutation(
        context: ModelContext,
        article: Article,
        previousState: ArticleStateSnapshot,
        mutation: ArticleStateMutation
    ) {
        refreshCounts(context: context)
        guard !matchesCurrentFeed(article) else {
            return
        }

        articles.removeAll { $0.id == article.id }
        displayItems.removeAll { $0.id == article.id }
        publishRenderItems()
        offset = articles.count
    }

    func shiftRenderWindowIfNeeded(localIndex: Int, context: ModelContext) {
        let globalIndex = renderWindow.globalIndex(forLocalIndex: localIndex)
        let shiftedWindow = renderWindow.shiftedIfNeeded(localIndex: localIndex, totalCount: displayItems.count)
        if shiftedWindow != renderWindow {
            renderWindow = shiftedWindow
            publishRenderItems()
        }
        loadMoreIfNeeded(currentIndex: globalIndex, context: context)
    }

    func refreshCounts(context: ModelContext) {
        do {
            let repository = SwiftDataArticleFeedRepository(context: context)
            counts = try repository.fetchCounts()
        } catch {
            counts = FeedCounts()
        }
    }

    func refreshTagNames(context: ModelContext) {
        do {
            let timing = StartupTimingRecorder()
            tagNames = try SwiftDataArticleFeedRepository(context: context).fetchTagNames()
            timing.markAndLog("Tag fetch")
        } catch {
            tagNames = []
        }
    }

    func reloadAfterBulkDataChange(context: ModelContext) {
        reload(context: context, filter: currentFilter, searchText: currentSearchText)
    }

    func beginPreparingFeed() {
        isPreparingFeed = true
    }

    func finishPreparingFeed() {
        isPreparingFeed = false
    }

    func prepareAfterRefresh(context: ModelContext, summary: FeedRefreshSummary) {
        defer { isPreparingFeed = false }
        pendingRefreshSummary = nil
        if summary.retentionDeletedCount > 0 {
            reloadAfterBulkDataChange(context: context)
        } else {
            mergeInsertedArticleIDs(summary.insertedArticleIDs, context: context)
        }
    }

    func prepareAfterSourceRefresh(context: ModelContext, summary: SourceRefreshSummary) {
        defer { isPreparingFeed = false }
        mergeInsertedArticleIDs(summary.insertedArticleIDs, context: context)
    }

    func storePendingRefresh(_ summary: FeedRefreshSummary) {
        guard summary.hasFeedChanges else {
            return
        }
        pendingRefreshSummary = summary
    }

    func dismissPendingRefresh() {
        pendingRefreshSummary = nil
    }

    func applyPendingRefresh(context: ModelContext) {
        guard let pendingRefreshSummary else {
            return
        }
        prepareAfterRefresh(context: context, summary: pendingRefreshSummary)
    }

    @discardableResult
    func cleanHome(context: ModelContext) throws -> ArticleCleanupResult {
        let result = try SwiftDataArticleRepository(context: context).deleteNonStarredArticles()
        reloadAfterBulkDataChange(context: context)
        return result
    }

    func mergeInsertedArticleIDs(_ articleIDs: [String], context: ModelContext) {
        refreshCounts(context: context)
        guard !articleIDs.isEmpty else {
            return
        }

        guard currentSearchText.isEmpty else {
            reloadAfterBulkDataChange(context: context)
            return
        }

        do {
            let repository = SwiftDataArticleFeedRepository(context: context)
            let insertedArticles = try repository.fetchArticles(ids: articleIDs)
            guard !insertedArticles.isEmpty else {
                return
            }

            let previousOffset = offset
            let previousHasMore = hasMore
            var articlesByID: [String: Article] = [:]
            for article in articles {
                articlesByID[article.id] = article
            }
            for article in insertedArticles {
                articlesByID[article.id] = article
            }

            let merged = ArticleSearchService().filter(
                articles: Array(articlesByID.values),
                filter: currentFilter,
                searchText: currentSearchText,
                sort: currentSort
            )
            let limit = max(Self.pageSize, previousOffset, articles.count)
            articles = Array(merged.prefix(limit))
            offset = max(previousOffset, articles.count)
            hasMore = previousHasMore
            rebuildDisplayItems(resetWindow: false)
        } catch {
            reloadAfterBulkDataChange(context: context)
        }
    }

    private func rebuildDisplayItems(resetWindow: Bool) {
        displayItems = articles.map(ArticleFeedDisplayItem.init(article:))
        if resetWindow {
            renderWindow = ArticleRenderWindow()
        }
        publishRenderItems()
    }

    private func appendDisplayItems(for articles: [Article]) {
        displayItems.append(contentsOf: articles.map(ArticleFeedDisplayItem.init(article:)))
        edgeResetGeneration += 1
        publishRenderItems()
    }

    private func publishRenderItems() {
        let range = renderWindow.range(totalCount: displayItems.count)
        renderItems = Array(displayItems[range])
    }

    private func matchesCurrentFeed(_ article: Article) -> Bool {
        !ArticleSearchService()
            .filter(articles: [article], filter: currentFilter, searchText: currentSearchText, sort: currentSort)
            .isEmpty
    }
}
