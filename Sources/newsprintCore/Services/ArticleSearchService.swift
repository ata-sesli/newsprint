import Foundation

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
        now: Date = Date()
    ) -> [Article] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let startOfToday = Calendar.current.startOfDay(for: now)

        return articles
            .filter { article in
                matches(filter: filter, article: article, startOfToday: startOfToday)
            }
            .filter { article in
                query.isEmpty || searchableText(for: article).contains(query)
            }
            .sorted(by: sortArticles)
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

    private func sortArticles(_ lhs: Article, _ rhs: Article) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        let lhsPublished = lhs.publishedAt ?? .distantPast
        let rhsPublished = rhs.publishedAt ?? .distantPast
        if lhsPublished != rhsPublished {
            return lhsPublished > rhsPublished
        }

        return lhs.fetchedAt > rhs.fetchedAt
    }
}

