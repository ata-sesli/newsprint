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

public struct ArticleFeedFamilySortBundle: Equatable, Sendable {
    public let all: ArticleFeedSortBundle
    public let hackerNews: ArticleFeedSortBundle
    public let nonHackerNews: ArticleFeedSortBundle

    public init(
        all: ArticleFeedSortBundle,
        hackerNews: ArticleFeedSortBundle,
        nonHackerNews: ArticleFeedSortBundle
    ) {
        self.all = all
        self.hackerNews = hackerNews
        self.nonHackerNews = nonHackerNews
    }

    public func page(kindFilter: ArticleFeedKindFilter, sort: ArticleFeedSort) -> ArticleFeedPageSnapshot {
        switch kindFilter {
        case .all:
            all.page(for: sort)
        case .hackerNews:
            hackerNews.page(for: sort)
        case .nonHackerNews:
            nonHackerNews.page(for: sort)
        }
    }
}

public struct ArticleFeedVariantBundle: Equatable, Sendable {
    public let feed: ArticleFeedFamilySortBundle
    public let starred: ArticleFeedFamilySortBundle

    public init(feed: ArticleFeedFamilySortBundle, starred: ArticleFeedFamilySortBundle) {
        self.feed = feed
        self.starred = starred
    }

    public func page(
        filter: ArticleFilter,
        kindFilter: ArticleFeedKindFilter,
        sort: ArticleFeedSort
    ) -> ArticleFeedPageSnapshot {
        switch filter {
        case .starred:
            starred.page(kindFilter: kindFilter, sort: sort)
        case .inbox, .unread, .today, .hidden, .source, .tag:
            feed.page(kindFilter: kindFilter, sort: sort)
        }
    }

    public func page(kindFilter: ArticleFeedKindFilter, sort: ArticleFeedSort) -> ArticleFeedPageSnapshot {
        feed.page(kindFilter: kindFilter, sort: sort)
    }
}

public struct ArticleFeedSortCacheKey: Hashable, Sendable {
    public let filter: ArticleFilter
    public let searchText: String
    public let offset: Int
    public let limit: Int

    public init(
        filter: ArticleFilter,
        searchText: String,
        offset: Int,
        limit: Int
    ) {
        self.filter = filter
        self.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

public struct ArticleFeedVariantKey: Hashable, Sendable {
    public let filter: ArticleFilter
    public let searchText: String
    public let sort: ArticleFeedSort
    public let kindFilter: ArticleFeedKindFilter

    public init(
        filter: ArticleFilter,
        searchText: String,
        sort: ArticleFeedSort,
        kindFilter: ArticleFeedKindFilter
    ) {
        self.filter = filter
        self.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sort = sort
        self.kindFilter = kindFilter
    }
}

public struct ArticleFeedVariantWindow: Equatable, Sendable {
    public let key: ArticleFeedVariantKey
    public let rows: [ArticleFeedRowSnapshot]
    public let start: Int
    public let nextOffset: Int
    public let hasMore: Bool

    public init(
        key: ArticleFeedVariantKey,
        rows: [ArticleFeedRowSnapshot],
        start: Int,
        nextOffset: Int,
        hasMore: Bool
    ) {
        self.key = key
        self.rows = rows
        self.start = max(0, start)
        self.nextOffset = nextOffset
        self.hasMore = hasMore
    }
}

public struct ArticleDetailSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let excerpt: String?
    public let contentHTML: String?
    public let contentText: String?
    public let authorCommentText: String?

    public init(
        id: String,
        excerpt: String?,
        contentHTML: String?,
        contentText: String?,
        authorCommentText: String?
    ) {
        self.id = id
        self.excerpt = excerpt
        self.contentHTML = contentHTML
        self.contentText = contentText
        self.authorCommentText = authorCommentText
    }

    public init(article: Article) {
        let metadata = HackerNewsMetadata(text: article.contentText ?? article.excerpt)
        let authorCommentText: String?
        if metadata != nil,
           let contentHTML = article.contentHTML,
           let text = HTMLTextExtractor.text(fromHTML: contentHTML)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty {
            authorCommentText = text
        } else if metadata != nil,
                  let excerpt = article.excerpt,
                  let text = HTMLTextExtractor.text(fromHTML: excerpt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty {
            authorCommentText = text
        } else {
            authorCommentText = metadata?.authorComment?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        self.init(
            id: article.id,
            excerpt: article.excerpt,
            contentHTML: article.contentHTML,
            contentText: article.contentText,
            authorCommentText: authorCommentText
        )
    }
}

public struct ArticleFeedRowSnapshot: Identifiable, Equatable, Sendable {
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
    public var isRead: Bool
    public var isStarred: Bool
    public var isHidden: Bool
    public let score: Double
    public let tagNames: [String]
    public let hackerNewsMetadata: HackerNewsMetadata?
    public let metadataText: String
    public let previewText: String?
    public let previewURL: URL
    public let hackerNewsAuthorCommentPreview: String?

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
        isRead: Bool,
        isStarred: Bool,
        isHidden: Bool,
        score: Double,
        tagNames: [String],
        hackerNewsMetadata: HackerNewsMetadata?,
        previewText: String?,
        hackerNewsAuthorCommentPreview: String?
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
        self.isRead = isRead
        self.isStarred = isStarred
        self.isHidden = isHidden
        self.score = score
        self.tagNames = tagNames
        self.hackerNewsMetadata = hackerNewsMetadata
        self.previewText = previewText
        self.hackerNewsAuthorCommentPreview = hackerNewsAuthorCommentPreview
        self.metadataText = Self.metadataText(
            sourceTitle: sourceTitle,
            author: author,
            date: publishedAt ?? fetchedAt
        )
        self.previewURL = hackerNewsMetadata?.articleURL ?? url
    }

    public init(article: Article, sourceKind: SourceKind?) {
        let metadata = HackerNewsMetadata(text: article.contentText ?? article.excerpt)
        let rowPreview: String?
        let authorCommentPreview: String?
        if metadata == nil {
            rowPreview = HTMLTextExtractor.text(fromHTML: article.contentText ?? article.excerpt)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty?
                .articleFeedPreviewSnippet
            authorCommentPreview = nil
        } else {
            rowPreview = nil
            if let contentHTML = article.contentHTML,
               let text = HTMLTextExtractor.text(fromHTML: contentHTML)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty {
                authorCommentPreview = text.articleFeedPreviewSnippet
            } else if let excerpt = article.excerpt,
                      let text = HTMLTextExtractor.text(fromHTML: excerpt)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty {
                authorCommentPreview = text.articleFeedPreviewSnippet
            } else {
                authorCommentPreview = metadata?.authorComment?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty?
                    .articleFeedPreviewSnippet
            }
        }

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
            isRead: article.isRead,
            isStarred: article.isStarred,
            isHidden: article.isHidden,
            score: article.score,
            tagNames: article.tagNames,
            hackerNewsMetadata: metadata,
            previewText: rowPreview,
            hackerNewsAuthorCommentPreview: authorCommentPreview
        )
    }

    public func applying(_ mutation: ArticleFeedSnapshotMutation) -> ArticleFeedRowSnapshot {
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
        hackerNewsAuthorCommentPreview
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

    var articleFeedPreviewSnippet: String {
        let normalized = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > 420 else {
            return normalized
        }
        let index = normalized.index(normalized.startIndex, offsetBy: 420)
        return String(normalized[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
