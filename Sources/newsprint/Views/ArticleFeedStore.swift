import Foundation
import SwiftData
import newsprintCore

@MainActor
final class ArticleFeedStore: ObservableObject {
    static let pageSize = 750
    static let loadMoreThreshold = 50

    @Published private(set) var articles: [Article] = []
    @Published private(set) var counts = FeedCounts()
    @Published private(set) var tagNames: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = true
    @Published private(set) var offset = 0
    @Published private(set) var bulkReloadGeneration = 0

    private var currentFilter: ArticleFilter = .inbox
    private var currentSearchText = ""
    private var currentSort: ArticleFeedSort = .hot
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
            offset = page.count
            hasMore = page.count == Self.pageSize
            counts = try repository.fetchCounts()
            timing.markAndLog("Count fetch")
            hasLoadedPage = true
            bulkReloadGeneration += 1
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            articles = []
            offset = 0
            hasMore = false
            hasLoadedPage = true
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
        offset = articles.count
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
        refreshTagNames(context: context)
    }

    private func matchesCurrentFeed(_ article: Article) -> Bool {
        !ArticleSearchService()
            .filter(articles: [article], filter: currentFilter, searchText: currentSearchText, sort: currentSort)
            .isEmpty
    }
}
