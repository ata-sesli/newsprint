import Foundation
import SwiftData

public actor ArticleFeedReadActor: ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    public init(modelContainer: ModelContainer) {
        let modelContext = ModelContext(modelContainer)
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
    }

    public func fetchPage(query: ArticleFeedQuery) throws -> ArticleFeedPageSnapshot {
        let normalizedSearch = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let articles: [Article]
        if !normalizedSearch.isEmpty || query.filter.requiresInMemoryFeedFiltering {
            articles = try fetchInMemoryFilteredPage(query: query, normalizedSearch: normalizedSearch)
        } else {
            var descriptor = FetchDescriptor<Article>(
                predicate: predicate(for: query.filter, now: query.now),
                sortBy: feedSortDescriptors(sort: query.sort)
            )
            descriptor.fetchOffset = query.offset
            descriptor.fetchLimit = query.limit
            articles = try modelContext.fetch(descriptor)
        }

        let sourceKinds = try sourceKindsByID(for: articles.map(\.sourceID))
        return ArticleFeedPageSnapshot(
            items: articles.map { ArticleFeedSnapshot(article: $0, sourceKind: sourceKinds[$0.sourceID]) },
            nextOffset: query.offset + articles.count,
            hasMore: articles.count == query.limit
        )
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

    public func fetchSnapshots(ids: [String]) throws -> [ArticleFeedSnapshot] {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else {
            return []
        }

        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                uniqueIDs.contains(article.id)
            }
        )
        let articles = try modelContext.fetch(descriptor)
        let sourceKinds = try sourceKindsByID(for: articles.map(\.sourceID))
        return articles.map { ArticleFeedSnapshot(article: $0, sourceKind: sourceKinds[$0.sourceID]) }
    }

    private func fetchInMemoryFilteredPage(query: ArticleFeedQuery, normalizedSearch: String) throws -> [Article] {
        let articles = try modelContext.fetch(FetchDescriptor<Article>(
            sortBy: feedSortDescriptors(sort: query.sort)
        ))
        let filtered = ArticleSearchService().filter(
            articles: articles,
            filter: query.filter,
            searchText: normalizedSearch,
            sort: query.sort,
            now: query.now
        )
        return Array(filtered.dropFirst(query.offset).prefix(query.limit))
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

    private func predicate(for filter: ArticleFilter, now: Date) -> Predicate<Article>? {
        switch filter {
        case .inbox:
            return #Predicate<Article> { article in
                !article.isHidden
            }
        case .unread:
            return #Predicate<Article> { article in
                !article.isRead && !article.isHidden
            }
        case .today:
            let startOfToday = Calendar.current.startOfDay(for: now)
            return #Predicate<Article> { article in
                !article.isHidden && article.fetchedAt >= startOfToday
            }
        case .starred:
            return #Predicate<Article> { article in
                article.isStarred
            }
        case .hidden:
            return #Predicate<Article> { article in
                article.isHidden
            }
        case .source(let sourceID):
            return #Predicate<Article> { article in
                article.sourceID == sourceID && !article.isHidden
            }
        case .tag:
            return nil
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

private extension ArticleFilter {
    var requiresInMemoryFeedFiltering: Bool {
        if case .tag = self {
            return true
        }
        return false
    }
}
