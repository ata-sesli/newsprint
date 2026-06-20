import Foundation

public struct ArticleFeedQuery: Equatable, Sendable {
    public let filter: ArticleFilter
    public let searchText: String
    public let offset: Int
    public let limit: Int
    public let sort: ArticleFeedSort
    public let kindFilter: ArticleFeedKindFilter
    public let now: Date

    public init(
        filter: ArticleFilter,
        searchText: String,
        offset: Int,
        limit: Int,
        sort: ArticleFeedSort,
        kindFilter: ArticleFeedKindFilter = .all,
        now: Date = Date()
    ) {
        self.filter = filter
        self.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.offset = max(0, offset)
        self.limit = max(0, limit)
        self.sort = sort
        self.kindFilter = kindFilter
        self.now = now
    }
}

public struct ArticleFeedPageSnapshot: Equatable, Sendable {
    public let items: [ArticleFeedSnapshot]
    public let nextOffset: Int
    public let hasMore: Bool

    public init(items: [ArticleFeedSnapshot], nextOffset: Int, hasMore: Bool) {
        self.items = items
        self.nextOffset = nextOffset
        self.hasMore = hasMore
    }
}

public struct ArticleFeedSortBundle: Equatable, Sendable {
    public let hot: ArticleFeedPageSnapshot
    public let newest: ArticleFeedPageSnapshot

    public init(hot: ArticleFeedPageSnapshot, newest: ArticleFeedPageSnapshot) {
        self.hot = hot
        self.newest = newest
    }

    public func page(for sort: ArticleFeedSort) -> ArticleFeedPageSnapshot {
        switch sort {
        case .hot:
            hot
        case .newest:
            newest
        }
    }
}

public struct ArticleFeedSortCacheKey: Hashable, Sendable {
    public let filter: ArticleFilter
    public let searchText: String
    public let kindFilter: ArticleFeedKindFilter
    public let offset: Int
    public let limit: Int

    public init(
        filter: ArticleFilter,
        searchText: String,
        kindFilter: ArticleFeedKindFilter,
        offset: Int,
        limit: Int
    ) {
        self.filter = filter
        self.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kindFilter = kindFilter
        self.offset = max(0, offset)
        self.limit = max(0, limit)
    }
}

public struct ArticleFeedSnapshotMutation: Equatable, Sendable {
    public var isRead: Bool?
    public var isStarred: Bool?
    public var isHidden: Bool?

    public init(isRead: Bool? = nil, isStarred: Bool? = nil, isHidden: Bool? = nil) {
        self.isRead = isRead
        self.isStarred = isStarred
        self.isHidden = isHidden
    }
}

public struct ArticleFeedSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceID: UUID
    public let sourceTitle: String
    public let sourceKind: SourceKind?
    public let title: String
    public let url: URL
    public let canonicalURL: URL?
    public let author: String?
    public let publishedAt: Date?
    public let fetchedAt: Date
    public let excerpt: String?
    public let contentHTML: String?
    public let contentText: String?
    public var isRead: Bool
    public var isStarred: Bool
    public var isHidden: Bool
    public let score: Double
    public let tagNames: [String]
    public let hackerNewsMetadata: HackerNewsMetadata?
    public let metadataText: String
    public let previewText: String?
    public let previewURL: URL

    public init(
        id: String,
        sourceID: UUID,
        sourceTitle: String,
        sourceKind: SourceKind?,
        title: String,
        url: URL,
        canonicalURL: URL?,
        author: String?,
        publishedAt: Date?,
        fetchedAt: Date,
        excerpt: String?,
        contentHTML: String?,
        contentText: String?,
        isRead: Bool,
        isStarred: Bool,
        isHidden: Bool,
        score: Double,
        tagNames: [String]
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.sourceKind = sourceKind
        self.title = title
        self.url = url
        self.canonicalURL = canonicalURL
        self.author = author
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.excerpt = excerpt
        self.contentHTML = contentHTML
        self.contentText = contentText
        self.isRead = isRead
        self.isStarred = isStarred
        self.isHidden = isHidden
        self.score = score
        self.tagNames = tagNames

        let metadata = HackerNewsMetadata(text: contentText ?? excerpt)
        self.hackerNewsMetadata = metadata
        self.metadataText = Self.metadataText(
            sourceTitle: sourceTitle,
            author: author,
            date: publishedAt ?? fetchedAt
        )
        if metadata == nil {
            self.previewText = HTMLTextExtractor.text(fromHTML: contentText ?? excerpt)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        } else {
            self.previewText = nil
        }
        self.previewURL = metadata?.articleURL ?? url
    }

    public init(article: Article, sourceKind: SourceKind?) {
        self.init(
            id: article.id,
            sourceID: article.sourceID,
            sourceTitle: article.sourceTitle,
            sourceKind: sourceKind,
            title: article.title,
            url: article.url,
            canonicalURL: article.canonicalURL,
            author: article.author,
            publishedAt: article.publishedAt,
            fetchedAt: article.fetchedAt,
            excerpt: article.excerpt,
            contentHTML: article.contentHTML,
            contentText: article.contentText,
            isRead: article.isRead,
            isStarred: article.isStarred,
            isHidden: article.isHidden,
            score: article.score,
            tagNames: article.tagNames
        )
    }

    public func applying(_ mutation: ArticleFeedSnapshotMutation) -> ArticleFeedSnapshot {
        var copy = self
        if let isRead = mutation.isRead {
            copy.isRead = isRead
        }
        if let isStarred = mutation.isStarred {
            copy.isStarred = isStarred
        }
        if let isHidden = mutation.isHidden {
            copy.isHidden = isHidden
        }
        return copy
    }

    public var hackerNewsAuthorCommentText: String? {
        guard hackerNewsMetadata != nil else {
            return nil
        }

        if let contentHTML,
           let text = HTMLTextExtractor.text(fromHTML: contentHTML)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty {
            return text
        }

        if let excerpt,
           let text = HTMLTextExtractor.text(fromHTML: excerpt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty {
            return text
        }

        return hackerNewsMetadata?.authorComment?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func metadataText(sourceTitle: String, author: String?, date: Date) -> String {
        var parts = [sourceTitle]
        if let author, !author.isEmpty {
            parts.append(author)
        }
        parts.append(date.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
