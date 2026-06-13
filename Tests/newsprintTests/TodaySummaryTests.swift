import Foundation
import Testing
@testable import newsprintCore

@Test func todaySummaryCountsArticles() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let todayUnread = makeSummaryArticle(id: "today-unread", fetchedAt: now, isRead: false)
    let todayRead = makeSummaryArticle(id: "today-read", fetchedAt: now, isRead: true)
    let oldStarred = makeSummaryArticle(id: "old-starred", fetchedAt: now.addingTimeInterval(-90_000), isStarred: true)
    let hidden = makeSummaryArticle(id: "hidden", fetchedAt: now, isHidden: true)

    let summary = TodaySummaryBuilder().summary(
        articles: [todayUnread, todayRead, oldStarred, hidden],
        sources: [],
        now: now
    )

    #expect(summary.todayCount == 3)
    #expect(summary.unreadCount == 3)
    #expect(summary.starredCount == 1)
    #expect(summary.hiddenCount == 1)
}

@Test func todaySummaryFrontPageExcludesHiddenAndReadAndSortsByRank() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let highScoreOld = makeSummaryArticle(
        id: "high",
        publishedAt: Date(timeIntervalSince1970: 100),
        fetchedAt: Date(timeIntervalSince1970: 100),
        score: 20
    )
    let lowScoreNew = makeSummaryArticle(
        id: "low",
        publishedAt: Date(timeIntervalSince1970: 300),
        fetchedAt: Date(timeIntervalSince1970: 300),
        score: 1
    )
    let read = makeSummaryArticle(id: "read", isRead: true, score: 99)
    let hidden = makeSummaryArticle(id: "hidden", isHidden: true, score: 99)

    let summary = TodaySummaryBuilder().summary(
        articles: [lowScoreNew, read, hidden, highScoreOld],
        sources: [],
        now: now
    )

    #expect(summary.frontPage.map(\.id) == ["high", "low"])
}

private func makeSummaryArticle(
    id: String,
    publishedAt: Date? = nil,
    fetchedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
    isRead: Bool = false,
    isStarred: Bool = false,
    isHidden: Bool = false,
    score: Double = 0
) -> Article {
    Article(
        id: id,
        sourceID: UUID(),
        sourceTitle: "Example",
        title: id,
        url: URL(string: "https://example.com/\(id)")!,
        publishedAt: publishedAt,
        fetchedAt: fetchedAt,
        isRead: isRead,
        isStarred: isStarred,
        isHidden: isHidden,
        score: score
    )
}
