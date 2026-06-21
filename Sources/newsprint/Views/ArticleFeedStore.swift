import Foundation
import SwiftData
import newsprintCore

@MainActor
final class ArticleFeedStore: ObservableObject {
    static let pageSize = 750
    static let loadMoreThreshold = 50

    @Published private(set) var renderItems: [ArticleFeedDisplayItem] = []
    @Published private(set) var detailsByID: [String: ArticleDetailSnapshot] = [:]
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

    private var cacheActor: ArticleFeedCacheActor?
    private var currentFilter: ArticleFilter = .inbox
    private var currentSearchText = ""
    private var currentSort: ArticleFeedSort = .hot
    private var currentKindFilter: ArticleFeedKindFilter = .all
    private var renderWindow = ArticleRenderWindow()
    private var cachedRowCount = 0
    private var rowsByID: [String: ArticleFeedDisplayItem] = [:]
    private var loadGeneration = 0
    private var hasLoadedPage = false
    private var loadTask: Task<Void, Never>?
    private var windowTask: Task<Void, Never>?
    private var countsTask: Task<Void, Never>?
    private var tagTask: Task<Void, Never>?
    private var pendingPrepareTask: Task<Void, Never>?
    private var warmupTask: Task<Void, Never>?
    private var detailTasks: [String: Task<Void, Never>] = [:]
    private var pendingPreparedSummary: FeedRefreshSummary?
    private var pendingPreparedWindow: ArticleFeedVariantWindow?

    deinit {
        loadTask?.cancel()
        windowTask?.cancel()
        countsTask?.cancel()
        tagTask?.cancel()
        pendingPrepareTask?.cancel()
        warmupTask?.cancel()
        detailTasks.values.forEach { $0.cancel() }
    }

    func configure(container: ModelContainer?) {
        guard cacheActor == nil, let container else {
            return
        }
        cacheActor = ArticleFeedCacheActor(modelContainer: container)
    }

    func reloadIfNeeded(
        filter: ArticleFilter,
        searchText: String,
        sort: ArticleFeedSort,
        kindFilter: ArticleFeedKindFilter
    ) {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasLoadedPage,
           currentSearchText == normalizedSearchText,
           currentFilter == filter,
           currentSort == sort,
           currentKindFilter == kindFilter {
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
        guard let cacheActor else {
            return
        }

        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedSort = sort ?? currentSort
        let selectedKindFilter = kindFilter ?? currentKindFilter
        currentFilter = filter
        currentSearchText = normalizedSearchText
        currentSort = selectedSort
        currentKindFilter = selectedKindFilter
        renderWindow = ArticleRenderWindow()
        cachedRowCount = 0
        offset = 0
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        windowTask?.cancel()
        pendingPrepareTask?.cancel()
        pendingPreparedSummary = nil
        pendingPreparedWindow = nil
        if renderItems.isEmpty {
            hasLoadedInitialPage = false
        }

        let query = activeQuery(start: 0, limit: ArticleRenderWindow.defaultSize)
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            do {
                async let window = cacheActor.loadActiveWindow(
                    query: query,
                    start: 0,
                    limit: ArticleRenderWindow.defaultSize
                )
                async let counts = cacheActor.fetchCounts()
                let result = try await (window, counts)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyActiveWindow(
                        result.0,
                        counts: result.1,
                        generation: generation,
                        resetScroll: true,
                        startWarmup: true
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
        let totalCountForShift = hasMore
            ? max(cachedRowCount + ArticleRenderWindow.defaultStride, renderWindow.end + ArticleRenderWindow.defaultStride)
            : cachedRowCount
        let shiftedWindow = renderWindow.shiftedIfNeeded(localIndex: localIndex, totalCount: totalCountForShift)
        guard shiftedWindow != renderWindow else {
            return
        }
        loadWindow(start: shiftedWindow.start, resetScroll: false)
    }

    func refreshCounts() {
        guard let cacheActor else {
            return
        }
        countsTask?.cancel()
        countsTask = Task { [weak self] in
            do {
                let counts = try await cacheActor.fetchCounts()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.counts = counts
                }
            } catch {}
        }
    }

    func refreshTagNames() {
        guard let cacheActor else {
            return
        }
        tagTask?.cancel()
        tagTask = Task { [weak self] in
            do {
                let timing = StartupTimingRecorder()
                let tagNames = try await cacheActor.fetchTagNames()
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
        guard let cacheActor else {
            reload(filter: currentFilter, searchText: currentSearchText, sort: currentSort, kindFilter: currentKindFilter)
            return
        }
        loadGeneration += 1
        let filter = currentFilter
        let searchText = currentSearchText
        let sort = currentSort
        let kindFilter = currentKindFilter
        Task { [weak self] in
            await cacheActor.invalidateAfterDataChange()
            await MainActor.run {
                self?.reload(filter: filter, searchText: searchText, sort: sort, kindFilter: kindFilter)
            }
        }
    }

    func beginPreparingFeed() {
        isPreparingFeed = true
    }

    func finishPreparingFeed() {
        isPreparingFeed = false
    }

    func prepareAfterRefresh(summary: FeedRefreshSummary) {
        pendingRefreshSummary = nil
        guard summary.hasFeedChanges else {
            refreshCounts()
            isPreparingFeed = false
            return
        }
        reloadAfterBulkDataChange()
    }

    func prepareAfterSourceRefresh(summary: SourceRefreshSummary) {
        guard summary.insertedCount > 0 else {
            refreshCounts()
            isPreparingFeed = false
            return
        }
        reloadAfterBulkDataChange()
    }

    func storePendingRefresh(_ summary: FeedRefreshSummary) {
        guard summary.hasFeedChanges else {
            return
        }
        pendingPrepareTask?.cancel()
        pendingRefreshSummary = nil
        pendingPreparedSummary = nil
        pendingPreparedWindow = nil

        guard summary.retentionDeletedCount == 0,
              !summary.insertedArticleIDs.isEmpty,
              let cacheActor else {
            return
        }

        let generation = loadGeneration
        let query = activeQuery(start: 0, limit: ArticleRenderWindow.defaultSize)
        pendingPrepareTask = Task { [weak self] in
            do {
                await cacheActor.invalidateAfterDataChange()
                let window = try await cacheActor.loadActiveWindow(
                    query: query,
                    start: 0,
                    limit: ArticleRenderWindow.defaultSize
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.storePreparedPendingRefresh(
                        summary,
                        window: window,
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
        pendingPreparedWindow = nil
    }

    func applyPendingRefresh() {
        guard let summary = pendingRefreshSummary else {
            return
        }
        pendingRefreshSummary = nil

        if pendingPreparedSummary == summary, let window = pendingPreparedWindow {
            pendingPreparedSummary = nil
            pendingPreparedWindow = nil
            pendingPrepareTask = nil
            applyActiveWindow(
                window,
                counts: counts,
                generation: loadGeneration,
                resetScroll: true,
                startWarmup: true
            )
            refreshCounts()
            isPreparingFeed = false
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
        return rowsByID[id] ?? renderItems.first { $0.id == id }
    }

    func detail(id: String?) -> ArticleDetailSnapshot? {
        guard let id else {
            return nil
        }
        return detailsByID[id]
    }

    func loadDetailIfNeeded(articleID: String?) {
        guard let articleID,
              detailsByID[articleID] == nil,
              detailTasks[articleID] == nil,
              let cacheActor else {
            return
        }

        detailTasks[articleID] = Task { [weak self] in
            do {
                let detail = try await cacheActor.detail(articleID: articleID)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.detailTasks[articleID] = nil
                    if let detail {
                        self?.detailsByID[articleID] = detail
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.detailTasks[articleID] = nil
                }
            }
        }
    }

    func applyMutation(articleID: String, mutation: ArticleFeedSnapshotMutation) {
        updateItem(articleID: articleID) { $0.applying(mutation) }
        if let cacheActor {
            Task {
                await cacheActor.invalidateAfterDataChange()
            }
        }
        refreshCounts()
        if let item = item(id: articleID), !matchesCurrentFeed(item) {
            rowsByID[articleID] = nil
            renderItems.removeAll { $0.id == articleID }
            cachedRowCount = max(0, cachedRowCount - 1)
            edgeResetGeneration += 1
        }
    }

    private func loadWindow(start: Int, resetScroll: Bool) {
        guard let cacheActor else {
            return
        }
        let generation = loadGeneration
        let normalizedStart = max(0, start)
        let query = activeQuery(start: normalizedStart, limit: ArticleRenderWindow.defaultSize)
        windowTask?.cancel()
        windowTask = Task { [weak self] in
            do {
                let window = try await cacheActor.loadActiveWindow(
                    query: query,
                    start: normalizedStart,
                    limit: ArticleRenderWindow.defaultSize
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyWindow(window, generation: generation, resetScroll: resetScroll)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.windowTask = nil
                    self?.hasMore = false
                }
            }
        }
    }

    private func activeQuery(start: Int, limit: Int) -> ArticleFeedQuery {
        ArticleFeedQuery(
            filter: currentFilter,
            searchText: currentSearchText,
            offset: start,
            limit: limit,
            sort: currentSort,
            kindFilter: currentKindFilter
        )
    }

    private func applyActiveWindow(
        _ window: ArticleFeedVariantWindow,
        counts: FeedCounts,
        generation: Int,
        resetScroll: Bool,
        startWarmup: Bool
    ) {
        guard generation == loadGeneration else {
            return
        }
        applyWindow(window, generation: generation, resetScroll: resetScroll)
        self.counts = counts
        hasLoadedPage = true
        hasLoadedInitialPage = true
        isLoading = false
        isPreparingFeed = false
        if startWarmup {
            scheduleWarmup(activeKey: window.key, generation: generation)
        }
    }

    private func applyWindow(
        _ window: ArticleFeedVariantWindow,
        generation: Int,
        resetScroll: Bool
    ) {
        guard generation == loadGeneration else {
            return
        }
        renderWindow = ArticleRenderWindow(start: window.start)
        renderItems = window.rows
        for row in window.rows {
            rowsByID[row.id] = row
        }
        cachedRowCount = max(cachedRowCount, window.nextOffset)
        offset = window.nextOffset
        hasMore = window.hasMore
        edgeResetGeneration += 1
        if resetScroll {
            bulkReloadGeneration += 1
        }
        windowTask = nil
    }

    private func applyReloadFailure(generation: Int) {
        guard generation == loadGeneration else {
            return
        }
        renderItems = []
        rowsByID.removeAll()
        renderWindow = ArticleRenderWindow()
        cachedRowCount = 0
        offset = 0
        hasMore = false
        hasLoadedPage = true
        hasLoadedInitialPage = true
        isLoading = false
        isPreparingFeed = false
    }

    private func storePreparedPendingRefresh(
        _ summary: FeedRefreshSummary,
        window: ArticleFeedVariantWindow,
        generation: Int
    ) {
        pendingPrepareTask = nil
        guard generation == loadGeneration else {
            return
        }
        pendingPreparedSummary = summary
        pendingPreparedWindow = window
        pendingRefreshSummary = summary
    }

    private func scheduleWarmup(activeKey: ArticleFeedVariantKey, generation: Int) {
        guard let cacheActor else {
            return
        }
        warmupTask?.cancel()
        let warmupQueries = warmupQueries(activeKey: activeKey)
        let activeIDs = Array(renderItems.prefix(50).map(\.id))
        warmupTask = Task.detached(priority: .utility) {
            await cacheActor.preloadDetails(articleIDs: activeIDs)
            for query in warmupQueries {
                guard !Task.isCancelled else { return }
                _ = try? await cacheActor.loadActiveWindow(
                    query: query,
                    start: 0,
                    limit: ArticleRenderWindow.defaultSize
                )
            }
            guard !Task.isCancelled else { return }
            await cacheActor.warmTail(activeKey, upTo: Self.pageSize)
        }
    }

    private func warmupQueries(activeKey: ArticleFeedVariantKey) -> [ArticleFeedQuery] {
        var keys: [ArticleFeedVariantKey] = []
        for filter in warmupFilters(for: currentFilter) {
            for kind in ArticleFeedKindFilter.allCases {
                for sort in ArticleFeedSort.allCases {
                    let key = ArticleFeedVariantKey(
                        filter: filter,
                        searchText: currentSearchText,
                        sort: sort,
                        kindFilter: kind
                    )
                    if key != activeKey {
                        keys.append(key)
                    }
                }
            }
        }

        return keys.map { key in
            ArticleFeedQuery(
                filter: key.filter,
                searchText: key.searchText,
                offset: 0,
                limit: ArticleRenderWindow.defaultSize,
                sort: key.sort,
                kindFilter: key.kindFilter
            )
        }
    }

    private func warmupFilters(for filter: ArticleFilter) -> [ArticleFilter] {
        if case .starred = filter {
            return [.starred, .inbox]
        }
        switch filter {
        case .inbox, .unread, .today, .hidden:
            return [filter, .starred]
        case .source, .tag:
            return [filter]
        case .starred:
            return [.starred]
        }
    }

    private func updateItem(articleID: String, update: (ArticleFeedDisplayItem) -> ArticleFeedDisplayItem) {
        if let item = rowsByID[articleID] {
            rowsByID[articleID] = update(item)
        }
        if let index = renderItems.firstIndex(where: { $0.id == articleID }) {
            let updated = update(renderItems[index])
            renderItems[index] = updated
            rowsByID[articleID] = updated
        }
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
            item.previewText,
            item.hackerNewsAuthorCommentPreview,
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
        case .nonHackerNews:
            return item.sourceKind != .hackerNews
        }
    }
}
