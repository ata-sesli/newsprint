import Foundation
import SwiftData

public struct FeedCounts: Equatable, Sendable {
    public let today: Int
    public let unread: Int
    public let starred: Int
    public let hidden: Int

    public init(today: Int = 0, unread: Int = 0, starred: Int = 0, hidden: Int = 0) {
        self.today = today
        self.unread = unread
        self.starred = starred
        self.hidden = hidden
    }
}

@MainActor
public struct SwiftDataArticleFeedRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func fetchPage(
        filter: ArticleFilter,
        searchText: String,
        offset: Int,
        limit: Int,
        sort: ArticleFeedSort = .hot,
        now: Date = Date()
    ) throws -> [Article] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedSearch.isEmpty || filter.requiresInMemoryFeedFiltering {
            return try fetchInMemoryFilteredPage(
                filter: filter,
                searchText: normalizedSearch,
                offset: offset,
                limit: limit,
                sort: sort,
                now: now
            )
        }

        var descriptor = FetchDescriptor<Article>(
            predicate: predicate(for: filter, now: now),
            sortBy: feedSortDescriptors(sort: sort)
        )
        descriptor.fetchOffset = max(0, offset)
        descriptor.fetchLimit = max(0, limit)
        return try context.fetch(descriptor)
    }

    public func fetchCounts(now: Date = Date()) throws -> FeedCounts {
        let startOfToday = Calendar.current.startOfDay(for: now)
        let today = try context.fetchCount(FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.fetchedAt >= startOfToday
            }
        ))
        let unread = try context.fetchCount(FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                !article.isRead
            }
        ))
        let starred = try context.fetchCount(FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.isStarred
            }
        ))
        let hidden = try context.fetchCount(FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.isHidden
            }
        ))
        return FeedCounts(today: today, unread: unread, starred: starred, hidden: hidden)
    }

    public func fetchTagNames() throws -> [String] {
        let articles = try context.fetch(FetchDescriptor<Article>())
        return Array(Set(articles.flatMap(\.tagNames))).sorted()
    }

    private func fetchInMemoryFilteredPage(
        filter: ArticleFilter,
        searchText: String,
        offset: Int,
        limit: Int,
        sort: ArticleFeedSort,
        now: Date
    ) throws -> [Article] {
        let articles = try context.fetch(FetchDescriptor<Article>(
            sortBy: feedSortDescriptors(sort: sort)
        ))
        let filtered = ArticleSearchService().filter(
            articles: articles,
            filter: filter,
            searchText: searchText,
            sort: sort,
            now: now
        )
        return Array(filtered.dropFirst(max(0, offset)).prefix(max(0, limit)))
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
            return todayPredicate(now: now)
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

    private func todayPredicate(now: Date) -> Predicate<Article> {
        let startOfToday = Calendar.current.startOfDay(for: now)
        return #Predicate<Article> { article in
            !article.isHidden && article.fetchedAt >= startOfToday
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
