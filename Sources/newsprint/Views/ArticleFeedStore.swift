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
    private var currentKindFilter: ArticleFeedKindFilter = .all
    private var renderWindow = ArticleRenderWindow()
    private var sortCache = ArticleFeedSortCache()
    private var currentSortCacheKey: ArticleFeedSortCacheKey?
    private var loadGeneration = 0
    private var hasLoadedPage = false
    private var loadTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var countsTask: Task<Void, Never>?
    private var tagTask: Task<Void, Never>?
    private var pendingPrepareTask: Task<Void, Never>?
    private var pendingPreparedSummary: FeedRefreshSummary?
    private var pendingPreparedInsertedItems: [ArticleFeedDisplayItem] = []

    deinit {
        loadTask?.cancel()
        prefetchTask?.cancel()
        countsTask?.cancel()
        tagTask?.cancel()
        pendingPrepareTask?.cancel()
    }

    func configure(container: ModelContainer?) {
        guard readActor == nil, let container else {
            return
        }
        readActor = ArticleFeedReadActor(modelContainer: container)
    }

    func reloadIfNeeded(
        filter: ArticleFilter,
        searchText: String,
        sort: ArticleFeedSort,
        kindFilter: ArticleFeedKindFilter
    ) {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasLoadedPage,
           currentFilter == filter,
           currentSearchText == normalizedSearchText,
           currentKindFilter == kindFilter,
           currentSort != sort {
            switchSort(sort)
            return
        }

        guard !hasLoadedPage ||
              currentFilter != filter ||
              currentSearchText != normalizedSearchText ||
              currentKindFilter != kindFilter else {
            currentSort = sort
            return
        }

        reload(filter: filter, searchText: normalizedSearchText, sort: sort, kindFilter: kindFilter)
    }

    func reload(
        filter: ArticleFilter,
        searchText: String,
        sort: ArticleFeedSort? = nil,
        kindFilter: ArticleFeedKindFilter? = nil
    ) {
        guard let readActor else {
            return
        }

        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedSort = sort ?? currentSort
        let selectedKindFilter = kindFilter ?? currentKindFilter
        currentFilter = filter
        currentSearchText = normalizedSearchText
        currentSort = selectedSort
        currentKindFilter = selectedKindFilter
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        prefetchTask?.cancel()
        pendingPrepareTask?.cancel()
        pendingPreparedSummary = nil
        pendingPreparedInsertedItems = []
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
                    sort: selectedSort,
                    kindFilter: selectedKindFilter
                )
                async let sortBundle = readActor.fetchSortBundle(query: query)
                async let counts = readActor.fetchCounts()
                let result = try await (sortBundle, counts)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyReload(
                        bundle: result.0,
                        counts: result.1,
                        key: ArticleFeedSortCacheKey(
                            filter: filter,
                            searchText: normalizedSearchText,
                            kindFilter: selectedKindFilter,
                            offset: 0,
                            limit: Self.pageSize
                        ),
                        generation: generation
                    )
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
        pendingPrepareTask?.cancel()
        pendingRefreshSummary = nil
        pendingPreparedSummary = nil
        pendingPreparedInsertedItems = []

        guard summary.retentionDeletedCount == 0,
              !summary.insertedArticleIDs.isEmpty,
              currentSearchText.isEmpty,
              let readActor else {
            return
        }

        let generation = loadGeneration
        pendingPrepareTask = Task { [weak self] in
            do {
                let insertedItems = try await readActor.fetchSnapshots(ids: summary.insertedArticleIDs)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.storePreparedPendingRefresh(
                        summary,
                        insertedItems: insertedItems,
                        generation: generation
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.pendingPrepareTask = nil
                }
            }
        }
    }

    func dismissPendingRefresh() {
        pendingRefreshSummary = nil
        pendingPrepareTask?.cancel()
        pendingPrepareTask = nil
        pendingPreparedSummary = nil
        pendingPreparedInsertedItems = []
    }

    func applyPendingRefresh() {
        guard let summary = pendingRefreshSummary else {
            return
        }
        pendingRefreshSummary = nil

        if pendingPreparedSummary == summary {
            let insertedItems = pendingPreparedInsertedItems
            pendingPreparedSummary = nil
            pendingPreparedInsertedItems = []
            pendingPrepareTask = nil
            refreshCounts()
            applyInsertedItems(insertedItems, generation: loadGeneration)
            return
        }

        prepareAfterRefresh(summary: summary)
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
            sort: currentSort,
            kindFilter: currentKindFilter
        )

        prefetchTask = Task { [weak self] in
            do {
                let bundle = try await readActor.fetchSortBundle(query: query)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyPrefetch(bundle: bundle, generation: generation)
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

    private func storePreparedPendingRefresh(
        _ summary: FeedRefreshSummary,
        insertedItems: [ArticleFeedDisplayItem],
        generation: Int
    ) {
        pendingPrepareTask = nil
        guard generation == loadGeneration else {
            return
        }
        pendingPreparedSummary = summary
        pendingPreparedInsertedItems = insertedItems
        pendingRefreshSummary = summary
    }

    private func switchSort(_ sort: ArticleFeedSort) {
        currentSort = sort
        guard let key = currentSortCacheKey,
              let bundle = sortCache.bundle(for: key) else {
            rebuildMissingSortCache()
            return
        }
        let page = bundle.page(for: sort)
        loadedItems = page.items
        offset = page.nextOffset
        hasMore = page.hasMore
        renderWindow = ArticleRenderWindow()
        publishRenderItems()
        bulkReloadGeneration += 1
    }

    private func rebuildMissingSortCache() {
        guard let readActor else {
            return
        }
        isPreparingFeed = true
        let generation = loadGeneration
        let key = ArticleFeedSortCacheKey(
            filter: currentFilter,
            searchText: currentSearchText,
            kindFilter: currentKindFilter,
            offset: 0,
            limit: Self.pageSize
        )
        let query = ArticleFeedQuery(
            filter: currentFilter,
            searchText: currentSearchText,
            offset: 0,
            limit: Self.pageSize,
            sort: currentSort,
            kindFilter: currentKindFilter
        )
        Task { [weak self] in
            do {
                let bundle = try await readActor.fetchSortBundle(query: query)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applySortCacheRebuild(bundle: bundle, key: key, generation: generation)
                }
            } catch {
                await MainActor.run {
                    self?.isPreparingFeed = false
                }
            }
        }
    }

    private func applySortCacheRebuild(
        bundle: ArticleFeedSortBundle,
        key: ArticleFeedSortCacheKey,
        generation: Int
    ) {
        guard generation == loadGeneration else {
            return
        }
        sortCache.store(bundle, for: key)
        currentSortCacheKey = key
        switchSort(currentSort)
        isPreparingFeed = false
    }

    private func applyReload(
        bundle: ArticleFeedSortBundle,
        counts: FeedCounts,
        key: ArticleFeedSortCacheKey,
        generation: Int
    ) {
        guard generation == loadGeneration else {
            return
        }
        sortCache.store(bundle, for: key)
        currentSortCacheKey = key
        let page = bundle.page(for: currentSort)
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

    private func applyPrefetch(bundle: ArticleFeedSortBundle, generation: Int) {
        guard generation == loadGeneration else {
            return
        }
        let page = bundle.page(for: currentSort)
        loadedItems.append(contentsOf: page.items)
        sortCache.append(bundle, currentKey: currentSortCacheKey)
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

        let limit = max(Self.pageSize, offset, loadedItems.count)
        var hotBuffer = TopCandidateBuffer<ArticleFeedDisplayItem>(
            limit: limit,
            areInPreferredOrder: { lhs, rhs in
                Self.isPreferred(lhs, rhs, sort: .hot)
            }
        )
        var newestBuffer = TopCandidateBuffer<ArticleFeedDisplayItem>(
            limit: limit,
            areInPreferredOrder: { lhs, rhs in
                Self.isPreferred(lhs, rhs, sort: .newest)
            }
        )
        hotBuffer.insert(contentsOf: itemsByID.values)
        newestBuffer.insert(contentsOf: itemsByID.values)

        let bundle = ArticleFeedSortBundle(
            hot: ArticleFeedPageSnapshot(
                items: hotBuffer.items,
                nextOffset: max(offset, hotBuffer.items.count),
                hasMore: hasMore
            ),
            newest: ArticleFeedPageSnapshot(
                items: newestBuffer.items,
                nextOffset: max(offset, newestBuffer.items.count),
                hasMore: hasMore
            )
        )
        sortCache.store(bundle, for: currentSortCacheKey)
        let page = bundle.page(for: currentSort)
        loadedItems = page.items
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
        matches(filter: currentFilter, item: item) && matches(kindFilter: currentKindFilter, item: item) && matchesSearch(item)
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

    private func matches(kindFilter: ArticleFeedKindFilter, item: ArticleFeedDisplayItem) -> Bool {
        switch kindFilter {
        case .all:
            return true
        case .hackerNews:
            return item.sourceKind == .hackerNews
        }
    }

    private static func isPreferred(
        _ lhs: ArticleFeedDisplayItem,
        _ rhs: ArticleFeedDisplayItem,
        sort: ArticleFeedSort
    ) -> Bool {
        switch sort {
        case .hot:
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return isNewer(lhs, rhs)
        case .newest:
            return isNewer(lhs, rhs)
        }
    }

    private static func isNewer(_ lhs: ArticleFeedDisplayItem, _ rhs: ArticleFeedDisplayItem) -> Bool {
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

struct ArticleFeedSortCache {
    private var bundles: [ArticleFeedSortCacheKey: ArticleFeedSortBundle] = [:]

    func bundle(for key: ArticleFeedSortCacheKey) -> ArticleFeedSortBundle? {
        bundles[key]
    }

    mutating func store(_ bundle: ArticleFeedSortBundle, for key: ArticleFeedSortCacheKey) {
        bundles[key] = bundle
    }

    mutating func append(_ bundle: ArticleFeedSortBundle, currentKey: ArticleFeedSortCacheKey?) {
        guard let currentKey, let existing = bundles[currentKey] else {
            return
        }
        bundles[currentKey] = ArticleFeedSortBundle(
            hot: ArticleFeedPageSnapshot(
                items: existing.hot.items + bundle.hot.items,
                nextOffset: bundle.hot.nextOffset,
                hasMore: bundle.hot.hasMore
            ),
            newest: ArticleFeedPageSnapshot(
                items: existing.newest.items + bundle.newest.items,
                nextOffset: bundle.newest.nextOffset,
                hasMore: bundle.newest.hasMore
            )
        )
    }

    mutating func store(_ bundle: ArticleFeedSortBundle, for key: ArticleFeedSortCacheKey?) {
        guard let key else {
            return
        }
        bundles[key] = bundle
    }
}
