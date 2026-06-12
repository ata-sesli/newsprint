import Foundation

public struct StarredArticleExporter {
    public init() {}

    public func markdown(for articles: [Article]) -> String {
        var lines = ["# Starred Articles", ""]
        for article in articles.filter(\.isStarred).sorted(by: sortArticles) {
            lines.append("- [\(article.title)](\(article.url.absoluteString))")
            lines.append("  - Source: \(article.sourceTitle)")
            if let date = article.publishedAt ?? article.updatedAt {
                lines.append("  - Date: \(ISO8601DateFormatter().string(from: date))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func sortArticles(_ lhs: Article, _ rhs: Article) -> Bool {
        (lhs.publishedAt ?? lhs.fetchedAt) > (rhs.publishedAt ?? rhs.fetchedAt)
    }
}

