import Foundation
import SwiftData

public actor ArticleFeedCacheActor: ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    private var rowCacheByID: [String: ArticleFeedRowSnapshot] = [:]
    private var detailCacheByID: [String: ArticleDetailSnapshot] = [:]
    private var variants: [ArticleFeedVariantKey: CachedVariant] = [:]
    private var queries: [ArticleFeedVariantKey: ArticleFeedQuery] = [:]
    private var warmingKeys: Set<ArticleFeedVariantKey> = []

    public init(modelContainer: ModelContainer) {
        let modelContext = ModelContext(modelContainer)
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
    }

    public func loadActiveWindow(
        query: ArticleFeedQuery,
        start: Int,
        limit: Int
    ) throws -> ArticleFeedVariantWindow {
        let key = query.variantKey
        queries[key] = query.with(offset: 0, limit: ArticleFeedCacheLimits.tailCount)
        try ensureVariant(key: key, query: query, minimumCount: start + limit)
        return window(for: key, start: start, limit: limit)
    }

    public func warmVariant(_ key: ArticleFeedVariantKey) async {
        guard !warmingKeys.contains(key), let query = queries[key] else {
            return
        }
        warmingKeys.insert(key)
        defer { warmingKeys.remove(key) }
        try? ensureVariant(key: key, query: query, minimumCount: ArticleFeedCacheLimits.visibleCount)
    }

    public func warmTail(_ key: ArticleFeedVariantKey, upTo limit: Int) async {
        guard !warmingKeys.contains(key), let query = queries[key] else {
            return
        }
        warmingKeys.insert(key)
        defer { warmingKeys.remove(key) }
        try? ensureVariant(
            key: key,
            query: query,
            minimumCount: min(max(limit, ArticleFeedCacheLimits.visibleCount), ArticleFeedCacheLimits.tailCount)
        )
    }

    public func preloadDetails(articleIDs: [String]) async {
        let uncachedIDs = articleIDs.filter { detailCacheByID[$0] == nil }
        guard !uncachedIDs.isEmpty else {
            return
        }
        _ = try? details(articleIDs: uncachedIDs)
    }

    public func detail(articleID: String) throws -> ArticleDetailSnapshot? {
        if let cached = detailCacheByID[articleID] {
            return cached
        }
        return try details(articleIDs: [articleID]).first
    }

    public func invalidateAfterDataChange() {
        rowCacheByID.removeAll()
        detailCacheByID.removeAll()
        variants.removeAll()
        queries.removeAll()
        warmingKeys.removeAll()
    }

    public func fetchCounts(now: Date = Date()) throws -> FeedCounts {
        let startOfToday = Calendar.current.startOfDay(for: now)
        let today = try modelContext.fetchCount(FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.fetchedAt >= startOfToday
            }
        ))
        let unread = try modelContext.fetchCount(FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                !article.isRead
            }
        ))
        let starred = try modelContext.fetchCount(FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.isStarred
            }
        ))
        let hidden = try modelContext.fetchCount(FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.isHidden
            }
        ))
        return FeedCounts(today: today, unread: unread, starred: starred, hidden: hidden)
    }

    public func fetchTagNames() throws -> [String] {
        let articles = try modelContext.fetch(FetchDescriptor<Article>())
        return Array(Set(articles.flatMap(\.tagNames))).sorted()
    }

    private func window(
        for key: ArticleFeedVariantKey,
        start: Int,
        limit: Int
    ) -> ArticleFeedVariantWindow {
        let variant = variants[key] ?? CachedVariant()
        let normalizedStart = max(0, start)
        let end = min(variant.ids.count, normalizedStart + max(0, limit))
        let ids = normalizedStart < end ? Array(variant.ids[normalizedStart..<end]) : []
        let rows = ids.compactMap { rowCacheByID[$0] }
        return ArticleFeedVariantWindow(
            key: key,
            rows: rows,
            start: normalizedStart,
            nextOffset: variant.ids.count,
            hasMore: variant.hasMore
        )
    }

    private func ensureVariant(
        key: ArticleFeedVariantKey,
        query: ArticleFeedQuery,
        minimumCount: Int
    ) throws {
        let target = min(max(minimumCount, ArticleFeedCacheLimits.visibleCount), ArticleFeedCacheLimits.tailCount)
        if let variant = variants[key], variant.ids.count >= target || !variant.hasMore {
            return
        }

        let rows = try fetchRows(query: query.with(offset: 0, limit: target))
        for row in rows {
            rowCacheByID[row.id] = row
        }
        variants[key] = CachedVariant(
            ids: rows.map(\.id),
            hasMore: rows.count == target
        )
    }

    private func fetchRows(query: ArticleFeedQuery) throws -> [ArticleFeedRowSnapshot] {
        let normalizedSearch = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let articles: [Article]
        if !normalizedSearch.isEmpty || query.filter.requiresInMemoryFeedFiltering {
            articles = try fetchInMemoryFilteredRows(query: query, normalizedSearch: normalizedSearch)
        } else {
            var descriptor = FetchDescriptor<Article>(
                predicate: try predicate(for: query.filter, kindFilter: query.kindFilter, now: query.now),
                sortBy: feedSortDescriptors(sort: query.sort)
            )
            descriptor.fetchOffset = query.offset
            descriptor.fetchLimit = query.limit
            articles = try modelContext.fetch(descriptor)
        }

        let sourceKinds = try sourceKindsByID(for: articles.map(\.sourceID))
        return articles.map { ArticleFeedRowSnapshot(article: $0, sourceKind: sourceKinds[$0.sourceID]) }
    }

    private func fetchInMemoryFilteredRows(query: ArticleFeedQuery, normalizedSearch: String) throws -> [Article] {
        let articles = try modelContext.fetch(FetchDescriptor<Article>(
            sortBy: feedSortDescriptors(sort: query.sort)
        ))
        let sourceKinds = try sourceKindsByID(for: articles.map(\.sourceID))
        let filtered = ArticleSearchService().filter(
            articles: articles,
            filter: query.filter,
            searchText: normalizedSearch,
            sort: query.sort,
            kindFilter: query.kindFilter,
            sourceKindsByID: sourceKinds,
            now: query.now
        )
        return Array(filtered.dropFirst(query.offset).prefix(query.limit))
    }

    private func details(articleIDs: [String]) throws -> [ArticleDetailSnapshot] {
        let uniqueIDs = Array(Set(articleIDs))
        guard !uniqueIDs.isEmpty else {
            return []
        }

        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                uniqueIDs.contains(article.id)
            }
        )
        let snapshots = try modelContext.fetch(descriptor).map(ArticleDetailSnapshot.init(article:))
        for snapshot in snapshots {
            detailCacheByID[snapshot.id] = snapshot
        }
        return snapshots
    }

    private func sourceKindsByID(for sourceIDs: [UUID]) throws -> [UUID: SourceKind] {
        let uniqueIDs = Array(Set(sourceIDs))
        guard !uniqueIDs.isEmpty else {
            return [:]
        }

        let descriptor = FetchDescriptor<Source>(
            predicate: #Predicate<Source> { source in
                uniqueIDs.contains(source.id)
            }
        )
        return try Dictionary(uniqueKeysWithValues: modelContext.fetch(descriptor).map { source in
            (source.id, source.kind)
        })
    }

    private func predicate(
        for filter: ArticleFilter,
        kindFilter: ArticleFeedKindFilter,
        now: Date
    ) throws -> Predicate<Article>? {
        let sourceIDs = try sourceIDs(for: kindFilter)
        switch filter {
        case .inbox:
            return #Predicate<Article> { article in
                !article.isHidden && sourceIDs.contains(article.sourceID)
            }
        case .unread:
            return #Predicate<Article> { article in
                !article.isRead && !article.isHidden && sourceIDs.contains(article.sourceID)
            }
        case .today:
            let startOfToday = Calendar.current.startOfDay(for: now)
            return #Predicate<Article> { article in
                !article.isHidden && article.fetchedAt >= startOfToday && sourceIDs.contains(article.sourceID)
            }
        case .starred:
            return #Predicate<Article> { article in
                article.isStarred && sourceIDs.contains(article.sourceID)
            }
        case .hidden:
            return #Predicate<Article> { article in
                article.isHidden && sourceIDs.contains(article.sourceID)
            }
        case .source(let sourceID):
            return #Predicate<Article> { article in
                article.sourceID == sourceID && !article.isHidden && sourceIDs.contains(article.sourceID)
            }
        case .tag:
            return nil
        }
    }

    private func sourceIDs(for kindFilter: ArticleFeedKindFilter) throws -> [UUID] {
        switch kindFilter {
        case .all:
            return try modelContext.fetch(FetchDescriptor<Source>()).map(\.id)
        case .hackerNews:
            let hackerNewsRawValue = SourceKind.hackerNews.rawValue
            return try modelContext.fetch(FetchDescriptor<Source>(
                predicate: #Predicate<Source> { source in
                    source.kindRawValue == hackerNewsRawValue
                }
            )).map(\.id)
        case .nonHackerNews:
            let hackerNewsRawValue = SourceKind.hackerNews.rawValue
            return try modelContext.fetch(FetchDescriptor<Source>(
                predicate: #Predicate<Source> { source in
                    source.kindRawValue != hackerNewsRawValue
                }
            )).map(\.id)
        }
    }

    private func feedSortDescriptors(sort: ArticleFeedSort) -> [SortDescriptor<Article>] {
        switch sort {
        case .hot:
            [
                SortDescriptor(\Article.score, order: .reverse),
                SortDescriptor(\Article.publishedAt, order: .reverse),
                SortDescriptor(\Article.fetchedAt, order: .reverse)
            ]
        case .newest:
            [
                SortDescriptor(\Article.publishedAt, order: .reverse),
                SortDescriptor(\Article.fetchedAt, order: .reverse),
                SortDescriptor(\Article.score, order: .reverse)
            ]
        }
    }
}

private struct CachedVariant: Sendable {
    var ids: [String] = []
    var hasMore = true
}

private enum ArticleFeedCacheLimits {
    static let visibleCount = 150
    static let tailCount = 750
}

private extension ArticleFilter {
    var requiresInMemoryFeedFiltering: Bool {
        if case .tag = self {
            return true
        }
        return false
    }
}

private extension ArticleFeedQuery {
    var variantKey: ArticleFeedVariantKey {
        ArticleFeedVariantKey(
            filter: filter,
            searchText: searchText,
            sort: sort,
            kindFilter: kindFilter
        )
    }

    func with(offset: Int, limit: Int) -> ArticleFeedQuery {
        ArticleFeedQuery(
            filter: filter,
            searchText: searchText,
            offset: offset,
            limit: limit,
            sort: sort,
            kindFilter: kindFilter,
            now: now
        )
    }
}
