import Foundation
import Testing
@testable import newsprintCore

@Test func searchMatchesArticleFields() {
    let article = makeSearchArticle(
        title: "SwiftData Reader",
        sourceTitle: "Example Source",
        author: "Taylor",
        contentText: "Local-first storage",
        tagNames: ["Swift"]
    )

    let service = ArticleSearchService()

    #expect(service.filter(articles: [article], filter: .inbox, searchText: "taylor").map(\.id) == [article.id])
    #expect(service.filter(articles: [article], filter: .inbox, searchText: "local-first").map(\.id) == [article.id])
    #expect(service.filter(articles: [article], filter: .inbox, searchText: "swift").map(\.id) == [article.id])
}

@Test func filtersAndSortsArticles() {
    let olderHighScore = makeSearchArticle(
        id: "older",
        title: "Older",
        publishedAt: Date(timeIntervalSince1970: 100),
        fetchedAt: Date(timeIntervalSince1970: 200),
        score: 10,
        tagNames: ["AI"]
    )
    let newerLowScore = makeSearchArticle(
        id: "newer",
        title: "Newer",
        publishedAt: Date(timeIntervalSince1970: 300),
        fetchedAt: Date(timeIntervalSince1970: 400),
        isRead: false,
        score: 1,
        tagNames: ["AI"]
    )

    let service = ArticleSearchService()
    let results = service.filter(
        articles: [newerLowScore, olderHighScore],
        filter: .tag("AI"),
        searchText: ""
    )

    #expect(results.map(\.id) == ["older", "newer"])
}

@Test func todayFilterUsesProvidedClock() {
    let now = Date(timeIntervalSince1970: 1_725_000_000)
    let today = makeSearchArticle(id: "today", title: "Today", fetchedAt: now)
    let old = makeSearchArticle(id: "old", title: "Old", fetchedAt: now.addingTimeInterval(-90_000))

    let results = ArticleSearchService().filter(
        articles: [today, old],
        filter: .today,
        searchText: "",
        now: now
    )

    #expect(results.map(\.id) == ["today"])
}

private func makeSearchArticle(
    id: String = UUID().uuidString,
    title: String,
    sourceTitle: String = "Source",
    author: String? = nil,
    contentText: String = "Local-first storage",
    publishedAt: Date? = nil,
    fetchedAt: Date = Date(),
    isRead: Bool = false,
    isStarred: Bool = false,
    isHidden: Bool = false,
    score: Double = 0,
    tagNames: [String] = []
) -> Article {
    Article(
        id: id,
        sourceID: UUID(),
        sourceTitle: sourceTitle,
        title: title,
        url: URL(string: "https://example.com/\(id)")!,
        author: author,
        publishedAt: publishedAt,
        fetchedAt: fetchedAt,
        contentText: contentText,
        isRead: isRead,
        isStarred: isStarred,
        isHidden: isHidden,
        score: score,
        tagNames: tagNames
    )
}
