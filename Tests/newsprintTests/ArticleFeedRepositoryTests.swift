import Foundation
import SwiftData
import Testing
@testable import newsprintCore

@MainActor
@Test func feedRepositoryPagesArticlesUsingFeedSortOrder() throws {
    let container = try feedTestContainer()
    let context = container.mainContext
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

    try insertFeedArticles(
        [
            makeFeedArticle(id: "low-new", sourceID: sourceID, score: 1, publishedAt: Date(timeIntervalSince1970: 300), fetchedAt: Date(timeIntervalSince1970: 300)),
            makeFeedArticle(id: "high-old", sourceID: sourceID, score: 10, publishedAt: Date(timeIntervalSince1970: 100), fetchedAt: Date(timeIntervalSince1970: 100)),
            makeFeedArticle(id: "mid", sourceID: sourceID, score: 5, publishedAt: Date(timeIntervalSince1970: 200), fetchedAt: Date(timeIntervalSince1970: 200))
        ],
        in: context
    )

    let repository = SwiftDataArticleFeedRepository(context: context)

    let firstPage = try repository.fetchPage(filter: .inbox, searchText: "", offset: 0, limit: 2, now: Date())
    let secondPage = try repository.fetchPage(filter: .inbox, searchText: "", offset: 2, limit: 2, now: Date())
    let newestPage = try repository.fetchPage(filter: .inbox, searchText: "", offset: 0, limit: 3, sort: .newest, now: Date())

    #expect(firstPage.map(\.id) == ["high-old", "mid"])
    #expect(secondPage.map(\.id) == ["low-new"])
    #expect(newestPage.map(\.id) == ["low-new", "mid", "high-old"])
}

@MainActor
@Test func feedRepositoryAppliesFiltersSearchAndCounts() throws {
    let container = try feedTestContainer()
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_717_200_000)
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
    let otherSourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!

    try insertFeedArticles(
        [
            makeFeedArticle(id: "unread-today", sourceID: sourceID, title: "Swift News", author: "Taylor", fetchedAt: now, tagNames: ["Swift"]),
            makeFeedArticle(id: "read", sourceID: sourceID, fetchedAt: now.addingTimeInterval(-60), isRead: true),
            makeFeedArticle(id: "starred", sourceID: otherSourceID, fetchedAt: now.addingTimeInterval(-90_000), isStarred: true),
            makeFeedArticle(id: "hidden", sourceID: sourceID, fetchedAt: now, isHidden: true)
        ],
        in: context
    )

    let repository = SwiftDataArticleFeedRepository(context: context)

    #expect(try repository.fetchPage(filter: .unread, searchText: "", offset: 0, limit: 10, now: now).map(\.id) == ["unread-today", "starred"])
    #expect(try repository.fetchPage(filter: .source(sourceID), searchText: "", offset: 0, limit: 10, now: now).map(\.id) == ["unread-today", "read"])
    #expect(try repository.fetchPage(filter: .tag("swift"), searchText: "", offset: 0, limit: 10, now: now).map(\.id) == ["unread-today"])
    #expect(try repository.fetchPage(filter: .inbox, searchText: "taylor", offset: 0, limit: 10, now: now).map(\.id) == ["unread-today"])

    let counts = try repository.fetchCounts(now: now)
    #expect(counts.today == 3)
    #expect(counts.unread == 3)
    #expect(counts.starred == 1)
    #expect(counts.hidden == 1)
}

@MainActor
private func feedTestContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Source.self, Article.self, AppSettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

@MainActor
private func insertFeedArticles(_ articles: [Article], in context: ModelContext) throws {
    for article in articles {
        context.insert(article)
    }
    try context.save()
}

private func makeFeedArticle(
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
