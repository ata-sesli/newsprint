import Foundation
import SwiftData

@Model
public final class Article {
    @Attribute(.unique) public var id: String
    public var sourceID: UUID
    public var sourceTitle: String
    public var title: String
    public var url: URL
    public var canonicalURL: URL?
    public var author: String?
    public var publishedAt: Date?
    public var updatedAt: Date?
    public var fetchedAt: Date
    public var excerpt: String?
    public var contentHTML: String?
    public var contentText: String?
    public var isRead: Bool
    public var isStarred: Bool
    public var isHidden: Bool
    public var score: Double
    public var matchedRuleIDs: [String]
    public var tagNames: [String]
    public var createdAt: Date

    public init(
        id: String,
        sourceID: UUID,
        sourceTitle: String,
        title: String,
        url: URL,
        canonicalURL: URL? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        updatedAt: Date? = nil,
        fetchedAt: Date = Date(),
        excerpt: String? = nil,
        contentHTML: String? = nil,
        contentText: String? = nil,
        isRead: Bool = false,
        isStarred: Bool = false,
        isHidden: Bool = false,
        score: Double = 0,
        matchedRuleIDs: [String] = [],
        tagNames: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.title = title
        self.url = url
        self.canonicalURL = canonicalURL
        self.author = author
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.fetchedAt = fetchedAt
        self.excerpt = excerpt
        self.contentHTML = contentHTML
        self.contentText = contentText
        self.isRead = isRead
        self.isStarred = isStarred
        self.isHidden = isHidden
        self.score = score
        self.matchedRuleIDs = matchedRuleIDs
        self.tagNames = tagNames
        self.createdAt = createdAt
    }

    public convenience init(draft: ArticleDraft, fetchedAt: Date = Date()) {
        self.init(draft: draft, ruleResult: RuleResult(), fetchedAt: fetchedAt)
    }

    public convenience init(draft: ArticleDraft, ruleResult: RuleResult, fetchedAt: Date = Date()) {
        let canonicalURL = URLCanonicalizer.canonicalize(draft.url)
        self.init(
            id: ArticleIDGenerator.id(for: draft),
            sourceID: draft.sourceID,
            sourceTitle: draft.sourceTitle,
            title: draft.title,
            url: draft.url,
            canonicalURL: canonicalURL,
            author: draft.author,
            publishedAt: draft.publishedAt,
            updatedAt: draft.updatedAt,
            fetchedAt: fetchedAt,
            excerpt: draft.excerpt,
            contentHTML: draft.contentHTML,
            contentText: draft.contentText,
            isRead: ruleResult.isRead,
            isStarred: ruleResult.isStarred,
            isHidden: ruleResult.isHidden,
            score: ruleResult.scoreDelta,
            matchedRuleIDs: ruleResult.matchedRuleIDs.map(\.uuidString),
            tagNames: ruleResult.tags
        )
    }
}
