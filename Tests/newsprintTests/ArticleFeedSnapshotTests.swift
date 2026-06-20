import Foundation
import Testing
@testable import newsprintCore

@Test func hackerNewsSnapshotAuthorCommentPrefersActualItemHTMLBeforeFallbacks() throws {
    let snapshot = ArticleFeedSnapshot(
        id: "hn-1",
        sourceID: UUID(),
        sourceTitle: "Hacker News Show",
        sourceKind: .hackerNews,
        title: "Show HN: Example",
        url: try #require(URL(string: "https://example.com")),
        canonicalURL: nil,
        author: "alice",
        publishedAt: Date(timeIntervalSince1970: 1_781_621_018),
        fetchedAt: Date(timeIntervalSince1970: 1_781_621_019),
        excerpt: "This fallback excerpt should not win.",
        contentHTML: "<p>This is the actual Firebase item text.</p><p>It keeps paragraph meaning.</p>",
        contentText: "Article URL: https://example.com Comments URL: https://news.ycombinator.com/item?id=1 Points: 42 # Comments: 3 Metadata fallback should not win.",
        isRead: false,
        isStarred: false,
        isHidden: false,
        score: 45,
        tagNames: []
    )

    #expect(snapshot.hackerNewsAuthorCommentText == "This is the actual Firebase item text. It keeps paragraph meaning.")
}

@Test func hackerNewsSnapshotAuthorCommentFallsBackToExcerptBeforeMetadata() throws {
    let snapshot = ArticleFeedSnapshot(
        id: "hn-2",
        sourceID: UUID(),
        sourceTitle: "Hacker News Show",
        sourceKind: .hackerNews,
        title: "Show HN: Example",
        url: try #require(URL(string: "https://example.com")),
        canonicalURL: nil,
        author: "alice",
        publishedAt: nil,
        fetchedAt: Date(timeIntervalSince1970: 1_781_621_019),
        excerpt: "This is the stored excerpt fallback.",
        contentHTML: nil,
        contentText: "Article URL: https://example.com Comments URL: https://news.ycombinator.com/item?id=2 Points: 42 # Comments: 3 Metadata fallback should not win.",
        isRead: false,
        isStarred: false,
        isHidden: false,
        score: 45,
        tagNames: []
    )

    #expect(snapshot.hackerNewsAuthorCommentText == "This is the stored excerpt fallback.")
}
