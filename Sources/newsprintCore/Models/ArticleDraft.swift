import Foundation

public struct ArticleDraft: Sendable {
    public let sourceID: UUID
    public let sourceTitle: String
    public let title: String
    public let url: URL
    public let author: String?
    public let publishedAt: Date?
    public let updatedAt: Date?
    public let excerpt: String?
    public let contentHTML: String?
    public let contentText: String?
    public let externalID: String?

    public init(
        sourceID: UUID,
        sourceTitle: String,
        title: String,
        url: URL,
        author: String?,
        publishedAt: Date?,
        updatedAt: Date?,
        excerpt: String?,
        contentHTML: String?,
        contentText: String?,
        externalID: String?
    ) {
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.title = title
        self.url = url
        self.author = author
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.excerpt = excerpt
        self.contentHTML = contentHTML
        self.contentText = contentText
        self.externalID = externalID
    }
}

