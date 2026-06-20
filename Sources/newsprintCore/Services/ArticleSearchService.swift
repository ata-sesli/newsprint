import Foundation

public enum ArticleFeedSort: String, Codable, CaseIterable, Sendable, Identifiable {
    case hot
    case newest

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hot:
            "Hot"
        case .newest:
            "Newest"
        }
    }
}

public enum ArticleFeedKindFilter: String, Codable, CaseIterable, Sendable, Identifiable {
    case all
    case hackerNews

    public var id: String { rawValue }
}

public enum ArticleFilter: Hashable, Sendable {
    case inbox
    case unread
    case today
    case starred
    case hidden
    case source(UUID)
    case tag(String)
}

public struct ArticleSearchService {
    public init() {}

    public func filter(
        articles: [Article],
        filter: ArticleFilter,
        searchText: String,
        sort: ArticleFeedSort = .hot,
        kindFilter: ArticleFeedKindFilter = .all,
        sourceKindsByID: [UUID: SourceKind] = [:],
        now: Date = Date()
    ) -> [Article] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let startOfToday = Calendar.current.startOfDay(for: now)

        return articles
            .filter { article in
                matches(filter: filter, article: article, startOfToday: startOfToday)
            }
            .filter { article in
                matches(kindFilter: kindFilter, article: article, sourceKindsByID: sourceKindsByID)
            }
            .filter { article in
                query.isEmpty || searchableText(for: article).contains(query)
            }
            .sorted { lhs, rhs in
                sortArticles(lhs, rhs, sort: sort)
            }
    }

    private func matches(
        kindFilter: ArticleFeedKindFilter,
        article: Article,
        sourceKindsByID: [UUID: SourceKind]
    ) -> Bool {
        switch kindFilter {
        case .all:
            return true
        case .hackerNews:
            return sourceKindsByID[article.sourceID] == .hackerNews
        }
    }

    private func matches(filter: ArticleFilter, article: Article, startOfToday: Date) -> Bool {
        switch filter {
        case .inbox:
            !article.isHidden
        case .unread:
            !article.isRead && !article.isHidden
        case .today:
            !article.isHidden && article.fetchedAt >= startOfToday
        case .starred:
            article.isStarred
        case .hidden:
            article.isHidden
        case .source(let id):
            article.sourceID == id && !article.isHidden
        case .tag(let tag):
            article.tagNames.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame } && !article.isHidden
        }
    }

    private func searchableText(for article: Article) -> String {
        [
            article.title,
            article.sourceTitle,
            article.author,
            article.excerpt,
            article.contentText,
            article.url.absoluteString,
            article.tagNames.joined(separator: " ")
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    private func sortArticles(_ lhs: Article, _ rhs: Article, sort: ArticleFeedSort) -> Bool {
        switch sort {
        case .hot:
            return sortHot(lhs, rhs)
        case .newest:
            return sortNewest(lhs, rhs)
        }
    }

    private func sortHot(_ lhs: Article, _ rhs: Article) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        return sortNewest(lhs, rhs)
    }

    private func sortNewest(_ lhs: Article, _ rhs: Article) -> Bool {
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
