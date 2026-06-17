import Foundation
import SwiftData
import Testing
@testable import newsprintCore

@MainActor
@Test func feedReadActorReturnsSnapshotsInFeedSortOrder() async throws {
    let container = try feedReadActorTestContainer()
    let context = container.mainContext
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000120")!
    context.insert(Source(
        id: sourceID,
        title: "Swift Source",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .blog
    ))
    try insertFeedReadActorArticles(
        [
            makeFeedReadActorArticle(id: "low-new", sourceID: sourceID, score: 1, publishedAt: Date(timeIntervalSince1970: 300), fetchedAt: Date(timeIntervalSince1970: 300)),
            makeFeedReadActorArticle(id: "high-old", sourceID: sourceID, score: 10, publishedAt: Date(timeIntervalSince1970: 100), fetchedAt: Date(timeIntervalSince1970: 100)),
            makeFeedReadActorArticle(id: "mid", sourceID: sourceID, score: 5, publishedAt: Date(timeIntervalSince1970: 200), fetchedAt: Date(timeIntervalSince1970: 200))
        ],
        in: context
    )

    let actor = ArticleFeedReadActor(modelContainer: container)
    let hotPage = try await actor.fetchPage(query: ArticleFeedQuery(
        filter: .inbox,
        searchText: "",
        offset: 0,
        limit: 2,
        sort: .hot
    ))
    let newestPage = try await actor.fetchPage(query: ArticleFeedQuery(
        filter: .inbox,
        searchText: "",
        offset: 0,
        limit: 3,
        sort: .newest
    ))

    #expect(hotPage.items.map(\.id) == ["high-old", "mid"])
    #expect(hotPage.nextOffset == 2)
    #expect(hotPage.hasMore)
    #expect(hotPage.items.first?.sourceKind == .blog)
    #expect(newestPage.items.map(\.id) == ["low-new", "mid", "high-old"])
}

@MainActor
@Test func feedReadActorAppliesSearchTagFiltersAndCountsOffMain() async throws {
    let container = try feedReadActorTestContainer()
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_717_200_000)
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000121")!
    let otherSourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000122")!
    context.insert(Source(
        id: sourceID,
        title: "Source",
        url: URL(string: "https://example.com/source.xml")!,
        kind: .rss
    ))
    context.insert(Source(
        id: otherSourceID,
        title: "Other",
        url: URL(string: "https://example.com/other.xml")!,
        kind: .atom
    ))
    try insertFeedReadActorArticles(
        [
            makeFeedReadActorArticle(id: "unread-today", sourceID: sourceID, title: "Swift News", author: "Taylor", fetchedAt: now, tagNames: ["Swift", "Programming"]),
            makeFeedReadActorArticle(id: "read", sourceID: sourceID, fetchedAt: now.addingTimeInterval(-60), isRead: true),
            makeFeedReadActorArticle(id: "starred", sourceID: otherSourceID, fetchedAt: now.addingTimeInterval(-90_000), isStarred: true, tagNames: ["Programming"]),
            makeFeedReadActorArticle(id: "hidden", sourceID: sourceID, fetchedAt: now, isHidden: true, tagNames: ["Hidden"])
        ],
        in: context
    )

    let actor = ArticleFeedReadActor(modelContainer: container)
    let tagPage = try await actor.fetchPage(query: ArticleFeedQuery(
        filter: .tag("swift"),
        searchText: "",
        offset: 0,
        limit: 10,
        sort: .hot,
        now: now
    ))
    let searchPage = try await actor.fetchPage(query: ArticleFeedQuery(
        filter: .inbox,
        searchText: "taylor",
        offset: 0,
        limit: 10,
        sort: .hot,
        now: now
    ))
    let counts = try await actor.fetchCounts(now: now)
    let tags = try await actor.fetchTagNames()

    #expect(tagPage.items.map(\.id) == ["unread-today"])
    #expect(searchPage.items.map(\.id) == ["unread-today"])
    #expect(counts == FeedCounts(today: 3, unread: 3, starred: 1, hidden: 1))
    #expect(tags == ["Hidden", "Programming", "Swift"])
}

@MainActor
private func feedReadActorTestContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Source.self, Article.self, AppSettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

@MainActor
private func insertFeedReadActorArticles(_ articles: [Article], in context: ModelContext) throws {
    for article in articles {
        context.insert(article)
    }
    try context.save()
}

private func makeFeedReadActorArticle(
    id: String,
    sourceID: UUID,
    title: String? = nil,
    author: String? = nil,
    score: Double = 0,
    publishedAt: Date? = nil,
    fetchedAt: Date = Date(),
    isRead: Bool = false,
    isStarred: Bool = false,
    isHidden: Bool = false,
    tagNames: [String] = []
) -> Article {
    Article(
        id: id,
        sourceID: sourceID,
        sourceTitle: "Source",
        title: title ?? id,
        url: URL(string: "https://example.com/\(id)")!,
        author: author,
        publishedAt: publishedAt,
        fetchedAt: fetchedAt,
        isRead: isRead,
        isStarred: isStarred,
        isHidden: isHidden,
        score: score,
        tagNames: tagNames
    )
}
