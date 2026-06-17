import Foundation
import SwiftData
import newsprintCore

@MainActor
final class ArticleFeedStore: ObservableObject {
    static let pageSize = 750
    static let loadMoreThreshold = 50

    @Published private(set) var loadedItems: [ArticleFeedDisplayItem] = []
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

    private var readActor: ArticleFeedReadActor?
    private var currentFilter: ArticleFilter = .inbox
    private var currentSearchText = ""
    private var currentSort: ArticleFeedSort = .hot
    private var renderWindow = ArticleRenderWindow()
    private var loadGeneration = 0
    private var hasLoadedPage = false
    private var loadTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var countsTask: Task<Void, Never>?
    private var tagTask: Task<Void, Never>?

    deinit {
        loadTask?.cancel()
        prefetchTask?.cancel()
        countsTask?.cancel()
        tagTask?.cancel()
    }

    func configure(container: ModelContainer?) {
        guard readActor == nil, let container else {
            return
        }
        readActor = ArticleFeedReadActor(modelContainer: container)
    }

    func reloadIfNeeded(filter: ArticleFilter, searchText: String, sort: ArticleFeedSort) {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hasLoadedPage ||
              currentFilter != filter ||
              currentSearchText != normalizedSearchText ||
              currentSort != sort else {
            return
        }

        reload(filter: filter, searchText: normalizedSearchText, sort: sort)
    }

    func reload(filter: ArticleFilter, searchText: String, sort: ArticleFeedSort? = nil) {
        guard let readActor else {
            return
        }

        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedSort = sort ?? currentSort
        currentFilter = filter
        currentSearchText = normalizedSearchText
        currentSort = selectedSort
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        prefetchTask?.cancel()
        if loadedItems.isEmpty {
            hasLoadedInitialPage = false
        }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            do {
                let query = ArticleFeedQuery(
                    filter: filter,
                    searchText: normalizedSearchText,
                    offset: 0,
                    limit: Self.pageSize,
                    sort: selectedSort
                )
                async let page = readActor.fetchPage(query: query)
                async let counts = readActor.fetchCounts()
                let result = try await (page, counts)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyReload(page: result.0, counts: result.1, generation: generation)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyReloadFailure(generation: generation)
                }
            }
        }
    }

    func shiftRenderWindowIfNeeded(localIndex: Int) {
        let globalIndex = renderWindow.globalIndex(forLocalIndex: localIndex)
        let shiftedWindow = renderWindow.shiftedIfNeeded(localIndex: localIndex, totalCount: loadedItems.count)
        if shiftedWindow != renderWindow {
            renderWindow = shiftedWindow
            publishRenderItems()
        }
        loadMoreIfNeeded(currentIndex: globalIndex)
    }

    func refreshCounts() {
        guard let readActor else {
            return
        }
        countsTask?.cancel()
        countsTask = Task { [weak self] in
            do {
                let counts = try await readActor.fetchCounts()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.counts = counts
                }
            } catch {}
        }
    }

    func refreshTagNames() {
        guard let readActor else {
            return
        }
        tagTask?.cancel()
        tagTask = Task { [weak self] in
            do {
                let timing = StartupTimingRecorder()
                let tagNames = try await readActor.fetchTagNames()
                timing.markAndLog("Tag fetch")
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.tagNames = tagNames
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.tagNames = []
                }
            }
        }
    }

    func reloadAfterBulkDataChange() {
        reload(filter: currentFilter, searchText: currentSearchText)
    }

    func beginPreparingFeed() {
        isPreparingFeed = true
    }

    func finishPreparingFeed() {
        isPreparingFeed = false
    }

    func prepareAfterRefresh(summary: FeedRefreshSummary) {
        pendingRefreshSummary = nil
        if summary.retentionDeletedCount > 0 {
            reloadAfterBulkDataChange()
        } else {
            mergeInsertedArticleIDs(summary.insertedArticleIDs)
        }
    }

    func prepareAfterSourceRefresh(summary: SourceRefreshSummary) {
        mergeInsertedArticleIDs(summary.insertedArticleIDs)
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

    func applyPendingRefresh() {
        guard let pendingRefreshSummary else {
            return
        }
        prepareAfterRefresh(summary: pendingRefreshSummary)
    }

    @discardableResult
    func cleanHome(context: ModelContext) throws -> ArticleCleanupResult {
        let result = try SwiftDataArticleRepository(context: context).deleteNonStarredArticles()
        reloadAfterBulkDataChange()
        return result
    }

    func item(id: String?) -> ArticleFeedDisplayItem? {
        guard let id else {
            return nil
        }
        return loadedItems.first { $0.id == id }
    }

    func applyMutation(articleID: String, mutation: ArticleFeedSnapshotMutation) {
        updateItem(articleID: articleID) { $0.applying(mutation) }
        refreshCounts()
        if let item = item(id: articleID), !matchesCurrentFeed(item) {
            loadedItems.removeAll { $0.id == articleID }
            publishRenderItems()
            offset = loadedItems.count
        }
    }

    private func loadMoreIfNeeded(currentIndex: Int) {
        guard let readActor,
              hasMore,
              !isLoading,
              prefetchTask == nil,
              currentIndex >= max(0, loadedItems.count - Self.loadMoreThreshold) else {
            return
        }

        isLoading = true
        let generation = loadGeneration
        let query = ArticleFeedQuery(
            filter: currentFilter,
            searchText: currentSearchText,
            offset: offset,
            limit: Self.pageSize,
            sort: currentSort
        )

        prefetchTask = Task { [weak self] in
            do {
                let page = try await readActor.fetchPage(query: query)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyPrefetch(page: page, generation: generation)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyPrefetchFailure(generation: generation)
                }
            }
        }
    }

    private func mergeInsertedArticleIDs(_ articleIDs: [String]) {
        refreshCounts()
        guard !articleIDs.isEmpty else {
            isPreparingFeed = false
            return
        }

        guard currentSearchText.isEmpty, let readActor else {
            reloadAfterBulkDataChange()
            return
        }

        let generation = loadGeneration
        Task { [weak self] in
            do {
                let insertedItems = try await readActor.fetchSnapshots(ids: articleIDs)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyInsertedItems(insertedItems, generation: generation)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.reloadAfterMergeFailure(generation: generation)
                }
            }
        }
    }

    private func applyReload(page: ArticleFeedPageSnapshot, counts: FeedCounts, generation: Int) {
        guard generation == loadGeneration else {
            return
        }
        loadedItems = page.items
        renderWindow = ArticleRenderWindow()
        publishRenderItems()
        offset = page.nextOffset
        hasMore = page.hasMore
        self.counts = counts
        hasLoadedPage = true
        hasLoadedInitialPage = true
        bulkReloadGeneration += 1
        isLoading = false
        isPreparingFeed = false
    }

    private func applyReloadFailure(generation: Int) {
        guard generation == loadGeneration else {
            return
        }
        loadedItems = []
        renderWindow = ArticleRenderWindow()
        publishRenderItems()
        offset = 0
        hasMore = false
        hasLoadedPage = true
        hasLoadedInitialPage = true
        isLoading = false
        isPreparingFeed = false
    }

    private func applyPrefetch(page: ArticleFeedPageSnapshot, generation: Int) {
        guard generation == loadGeneration else {
            return
        }
        loadedItems.append(contentsOf: page.items)
        offset = page.nextOffset
        hasMore = page.hasMore
        edgeResetGeneration += 1
        publishRenderItems()
        isLoading = false
        prefetchTask = nil
    }

    private func applyPrefetchFailure(generation: Int) {
        guard generation == loadGeneration else {
            return
        }
        hasMore = false
        isLoading = false
        prefetchTask = nil
    }

    private func applyInsertedItems(_ insertedItems: [ArticleFeedDisplayItem], generation: Int) {
        guard generation == loadGeneration else {
            return
        }
        guard !insertedItems.isEmpty else {
            isPreparingFeed = false
            return
        }

        var itemsByID: [String: ArticleFeedDisplayItem] = [:]
        for item in loadedItems {
            itemsByID[item.id] = item
        }
        for item in insertedItems where matchesCurrentFeed(item) {
            itemsByID[item.id] = item
        }

        let merged = sortItems(Array(itemsByID.values), sort: currentSort)
        let limit = max(Self.pageSize, offset, loadedItems.count)
        loadedItems = Array(merged.prefix(limit))
        offset = max(offset, loadedItems.count)
        publishRenderItems()
        isPreparingFeed = false
    }

    private func reloadAfterMergeFailure(generation: Int) {
        guard generation == loadGeneration else {
            return
        }
        reloadAfterBulkDataChange()
    }

    private func updateItem(articleID: String, update: (ArticleFeedDisplayItem) -> ArticleFeedDisplayItem) {
        if let index = loadedItems.firstIndex(where: { $0.id == articleID }) {
            loadedItems[index] = update(loadedItems[index])
        }
        if let index = renderItems.firstIndex(where: { $0.id == articleID }) {
            renderItems[index] = update(renderItems[index])
        }
    }

    private func publishRenderItems() {
        let range = renderWindow.range(totalCount: loadedItems.count)
        renderItems = Array(loadedItems[range])
    }

    private func matchesCurrentFeed(_ item: ArticleFeedDisplayItem) -> Bool {
        matches(filter: currentFilter, item: item) && matchesSearch(item)
    }

    private func matchesSearch(_ item: ArticleFeedDisplayItem) -> Bool {
        let query = currentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return true
        }
        return [
            item.title,
            item.sourceTitle,
            item.author,
            item.excerpt,
            item.contentText,
            item.url.absoluteString,
            item.tagNames.joined(separator: " ")
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            .contains(query)
    }

    private func matches(filter: ArticleFilter, item: ArticleFeedDisplayItem) -> Bool {
        switch filter {
        case .inbox:
            return !item.isHidden
        case .unread:
            return !item.isRead && !item.isHidden
        case .today:
            return !item.isHidden && item.fetchedAt >= Calendar.current.startOfDay(for: Date())
        case .starred:
            return item.isStarred
        case .hidden:
            return item.isHidden
        case .source(let sourceID):
            return item.sourceID == sourceID && !item.isHidden
        case .tag(let tag):
            return item.tagNames.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame } && !item.isHidden
        }
    }

    private func sortItems(_ items: [ArticleFeedDisplayItem], sort: ArticleFeedSort) -> [ArticleFeedDisplayItem] {
        items.sorted { lhs, rhs in
            switch sort {
            case .hot:
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return newest(lhs, rhs)
            case .newest:
                return newest(lhs, rhs)
            }
        }
    }

    private func newest(_ lhs: ArticleFeedDisplayItem, _ rhs: ArticleFeedDisplayItem) -> Bool {
        let lhsPublished = lhs.publishedAt ?? .distantPast
        let rhsPublished = rhs.publishedAt ?? .distantPast
        if lhsPublished != rhsPublished {
            return lhsPublished > rhsPublished
        }
        if lhs.fetchedAt != rhs.fetchedAt {
            return lhs.fetchedAt > rhs.fetchedAt
        }
        return lhs.score > rhs.score
    }
}
