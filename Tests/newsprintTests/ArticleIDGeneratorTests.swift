import Testing
import Foundation
@testable import newsprintCore

@Test func articleIDUsesCanonicalURLBeforeExternalID() throws {
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let draft = ArticleDraft(
        sourceID: sourceID,
        sourceTitle: "Example",
        title: "Post",
        url: try #require(URL(string: "https://example.com/post?utm_medium=social&id=1")),
        author: nil,
        publishedAt: nil,
        updatedAt: nil,
        excerpt: nil,
        contentHTML: nil,
        contentText: nil,
        externalID: "feed-guid"
    )

    let articleID = ArticleIDGenerator.id(for: draft)

    #expect(articleID == "https://example.com/post?id=1")
}

@Test func articleIDFallsBackToExternalIDWhenURLIsNotHTTP() throws {
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let draft = ArticleDraft(
        sourceID: sourceID,
        sourceTitle: "Example",
        title: "Post",
        url: try #require(URL(string: "about:blank")),
        author: nil,
        publishedAt: nil,
        updatedAt: nil,
        excerpt: nil,
        contentHTML: nil,
        contentText: nil,
        externalID: "feed-guid"
    )

    let articleID = ArticleIDGenerator.id(for: draft)

    #expect(articleID == "feed-guid")
}

