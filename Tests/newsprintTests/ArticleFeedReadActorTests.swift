import Foundation
import SwiftData
import Testing
@testable import newsprintCore

@MainActor
@Test func feedReadActorFetchesOnlyActiveVariantPage() async throws {
    let container = try feedReadActorTestContainer()
    let context = container.mainContext
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000130")!
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
    let page = try await actor.fetchActiveVariant(query: ArticleFeedQuery(
        filter: .inbox,
        searchText: "",
        offset: 0,
        limit: 2,
        sort: .hot
    ))

    #expect(page.items.map(\.id) == ["high-old", "mid"])
    #expect(page.nextOffset == 2)
    #expect(page.hasMore)
}

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
@Test func feedReadActorBuildsHotAndNewestSortBundleFromOneQuery() async throws {
    let container = try feedReadActorTestContainer()
    let context = container.mainContext
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000125")!
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
    let bundle = try await actor.fetchSortBundle(query: ArticleFeedQuery(
        filter: .inbox,
        searchText: "",
        offset: 0,
        limit: 3,
        sort: .hot
    ))

    #expect(bundle.hot.items.map(\.id) == ["high-old", "mid", "low-new"])
    #expect(bundle.newest.items.map(\.id) == ["low-new", "mid", "high-old"])
    #expect(bundle.hot.nextOffset == 3)
    #expect(bundle.newest.nextOffset == 3)
}

@MainActor
@Test func feedReadActorBuildsFamilyVariantBundleForHotAndNewest() async throws {
    let container = try feedReadActorTestContainer()
    let context = container.mainContext
    let hackerNewsSourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000126")!
    let blogSourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000127")!
    context.insert(Source(
        id: hackerNewsSourceID,
        title: "Hacker News",
        url: URL(string: "https://hacker-news.firebaseio.com/v0/topstories.json")!,
        kind: .hackerNews
    ))
    context.insert(Source(
        id: blogSourceID,
        title: "Blog",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .blog
    ))
    try insertFeedReadActorArticles(
        [
            makeFeedReadActorArticle(id: "hn-hot", sourceID: hackerNewsSourceID, score: 20, publishedAt: Date(timeIntervalSince1970: 100)),
            makeFeedReadActorArticle(id: "hn-new", sourceID: hackerNewsSourceID, score: 1, publishedAt: Date(timeIntervalSince1970: 400)),
            makeFeedReadActorArticle(id: "blog-hot", sourceID: blogSourceID, score: 30, publishedAt: Date(timeIntervalSince1970: 200)),
            makeFeedReadActorArticle(id: "blog-new", sourceID: blogSourceID, score: 2, publishedAt: Date(timeIntervalSince1970: 500))
        ],
        in: context
    )

    let actor = ArticleFeedReadActor(modelContainer: container)
    let bundle = try await actor.fetchVariantBundle(query: ArticleFeedQuery(
        filter: .inbox,
        searchText: "",
        offset: 0,
        limit: 10,
        sort: .hot
    ))

    #expect(bundle.page(kindFilter: .all, sort: .hot).items.map(\.id) == ["blog-hot", "hn-hot", "blog-new", "hn-new"])
    #expect(bundle.page(kindFilter: .all, sort: .newest).items.map(\.id) == ["blog-new", "hn-new", "blog-hot", "hn-hot"])
    #expect(bundle.page(kindFilter: .hackerNews, sort: .hot).items.map(\.id) == ["hn-hot", "hn-new"])
    #expect(bundle.page(kindFilter: .hackerNews, sort: .newest).items.map(\.id) == ["hn-new", "hn-hot"])
    #expect(bundle.page(kindFilter: .nonHackerNews, sort: .hot).items.map(\.id) == ["blog-hot", "blog-new"])
    #expect(bundle.page(kindFilter: .nonHackerNews, sort: .newest).items.map(\.id) == ["blog-new", "blog-hot"])
}

@MainActor
@Test func feedReadActorBuildsStarredFamilyVariantBundleForHotAndNewest() async throws {
    let container = try feedReadActorTestContainer()
    let context = container.mainContext
    let hackerNewsSourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000128")!
    let blogSourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000129")!
    context.insert(Source(
        id: hackerNewsSourceID,
        title: "Hacker News",
        url: URL(string: "https://hacker-news.firebaseio.com/v0/topstories.json")!,
        kind: .hackerNews
    ))
    context.insert(Source(
        id: blogSourceID,
        title: "Blog",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .blog
    ))
    try insertFeedReadActorArticles(
        [
            makeFeedReadActorArticle(id: "hn-star-hot", sourceID: hackerNewsSourceID, score: 20, publishedAt: Date(timeIntervalSince1970: 100), isStarred: true),
            makeFeedReadActorArticle(id: "hn-unstarred", sourceID: hackerNewsSourceID, score: 50, publishedAt: Date(timeIntervalSince1970: 600)),
            makeFeedReadActorArticle(id: "blog-star-new", sourceID: blogSourceID, score: 2, publishedAt: Date(timeIntervalSince1970: 500), isStarred: true),
            makeFeedReadActorArticle(id: "blog-star-hot", sourceID: blogSourceID, score: 30, publishedAt: Date(timeIntervalSince1970: 200), isStarred: true)
        ],
        in: context
    )

    let actor = ArticleFeedReadActor(modelContainer: container)
    let bundle = try await actor.fetchVariantBundle(query: ArticleFeedQuery(
        filter: .inbox,
        searchText: "",
        offset: 0,
        limit: 10,
        sort: .hot
    ))

    #expect(bundle.starred.page(kindFilter: .all, sort: .hot).items.map(\.id) == ["blog-star-hot", "hn-star-hot", "blog-star-new"])
    #expect(bundle.starred.page(kindFilter: .all, sort: .newest).items.map(\.id) == ["blog-star-new", "blog-star-hot", "hn-star-hot"])
    #expect(bundle.starred.page(kindFilter: .hackerNews, sort: .hot).items.map(\.id) == ["hn-star-hot"])
    #expect(bundle.starred.page(kindFilter: .nonHackerNews, sort: .newest).items.map(\.id) == ["blog-star-new", "blog-star-hot"])
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
@Test func feedReadActorFiltersHackerNewsSourceFamily() async throws {
    let container = try feedReadActorTestContainer()
    let context = container.mainContext
    let hackerNewsSourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
    let blogSourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000124")!
    context.insert(Source(
        id: hackerNewsSourceID,
        title: "Hacker News Show",
        url: URL(string: "https://hacker-news.firebaseio.com/v0/showstories.json")!,
        kind: .hackerNews
    ))
    context.insert(Source(
        id: blogSourceID,
        title: "Blog",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .blog
    ))
    try insertFeedReadActorArticles(
        [
            makeFeedReadActorArticle(id: "hn-high", sourceID: hackerNewsSourceID, title: "HN High", score: 100, tagNames: ["AI"]),
            makeFeedReadActorArticle(id: "hn-low", sourceID: hackerNewsSourceID, title: "HN Low", score: 1, isRead: true),
            makeFeedReadActorArticle(id: "blog-high", sourceID: blogSourceID, title: "Blog High", score: 200, tagNames: ["AI"])
        ],
        in: context
    )

    let actor = ArticleFeedReadActor(modelContainer: container)
    let hnHotPage = try await actor.fetchPage(query: ArticleFeedQuery(
        filter: .inbox,
        searchText: "",
        offset: 0,
        limit: 10,
        sort: .hot,
        kindFilter: .hackerNews
    ))
    let hnUnreadPage = try await actor.fetchPage(query: ArticleFeedQuery(
        filter: .unread,
        searchText: "",
        offset: 0,
        limit: 10,
        sort: .hot,
        kindFilter: .hackerNews
    ))
    let allHotPage = try await actor.fetchPage(query: ArticleFeedQuery(
        filter: .inbox,
        searchText: "",
        offset: 0,
        limit: 10,
        sort: .hot,
        kindFilter: .all
    ))
    let nonHackerNewsPage = try await actor.fetchPage(query: ArticleFeedQuery(
        filter: .inbox,
        searchText: "",
        offset: 0,
        limit: 10,
        sort: .hot,
        kindFilter: .nonHackerNews
    ))

    #expect(hnHotPage.items.map(\.id) == ["hn-high", "hn-low"])
    #expect(hnUnreadPage.items.map(\.id) == ["hn-high"])
    #expect(allHotPage.items.map(\.id) == ["blog-high", "hn-high", "hn-low"])
    #expect(nonHackerNewsPage.items.map(\.id) == ["blog-high"])
}

@MainActor
@Test func feedCacheActorReturnsOnlyVisibleWindowRows() async throws {
    let container = try feedReadActorTestContainer()
    let context = container.mainContext
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000140")!
    context.insert(Source(
        id: sourceID,
        title: "Blog",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .blog
    ))

    let articles = (0..<200).map { index in
        makeFeedReadActorArticle(
            id: String(format: "item-%03d", index),
            sourceID: sourceID,
            score: Double(200 - index),
            publishedAt: Date(timeIntervalSince1970: TimeInterval(10_000 - index)),
            fetchedAt: Date(timeIntervalSince1970: TimeInterval(10_000 - index))
        )
    }
    try insertFeedReadActorArticles(articles, in: context)

    let actor = ArticleFeedCacheActor(modelContainer: container)
    let query = ArticleFeedQuery(
        filter: .inbox,
        searchText: "",
        offset: 0,
        limit: 150,
        sort: .hot
    )
    let firstWindow = try await actor.loadActiveWindow(query: query, start: 0, limit: 150)
    let shiftedWindow = try await actor.loadActiveWindow(query: query, start: 50, limit: 150)

    #expect(firstWindow.rows.count == 150)
    #expect(firstWindow.rows.first?.id == "item-000")
    #expect(firstWindow.rows.last?.id == "item-149")
    #expect(shiftedWindow.rows.count == 150)
    #expect(shiftedWindow.rows.first?.id == "item-050")
    #expect(shiftedWindow.rows.last?.id == "item-199")
}

@MainActor
@Test func feedCacheActorKeepsFullArticleBodyInDetailSnapshot() async throws {
    let container = try feedReadActorTestContainer()
    let context = container.mainContext
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000141")!
    context.insert(Source(
        id: sourceID,
        title: "Longform",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .blog
    ))
    let longText = Array(repeating: "This is a deliberately long paragraph for the full article body.", count: 40)
        .joined(separator: " ")
    let longHTML = "<article><p>\(longText)</p></article>"
    context.insert(Article(
        id: "long-body",
        sourceID: sourceID,
        sourceTitle: "Longform",
        title: "Long Body",
        url: URL(string: "https://example.com/long-body")!,
        publishedAt: Date(timeIntervalSince1970: 500),
        fetchedAt: Date(timeIntervalSince1970: 500),
        excerpt: "Short excerpt",
        contentHTML: longHTML,
        contentText: longText,
        score: 10
    ))
    try context.save()

    let actor = ArticleFeedCacheActor(modelContainer: container)
    let window = try await actor.loadActiveWindow(
        query: ArticleFeedQuery(
            filter: .inbox,
            searchText: "",
            offset: 0,
            limit: 150,
            sort: .hot
        ),
        start: 0,
        limit: 150
    )
    let row = try #require(window.rows.first)
    let detail = try #require(try await actor.detail(articleID: "long-body"))

    #expect(row.id == "long-body")
    #expect(row.previewText != longText)
    #expect((row.previewText?.count ?? 0) <= 423)
    #expect(detail.contentText == longText)
    #expect(detail.contentHTML == longHTML)
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
