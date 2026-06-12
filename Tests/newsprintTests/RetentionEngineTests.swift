import Foundation
import SwiftData
import Testing
@testable import newsprintCore

@MainActor
@Test func retentionDeletesOldUnstarredArticles() throws {
    let container = try testContainer()
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_717_200_000)
    let oldUnstarred = makeArticle(id: "old-unstarred", fetchedAt: now.addingTimeInterval(-8 * 86_400))
    let oldStarred = makeArticle(id: "old-starred", fetchedAt: now.addingTimeInterval(-8 * 86_400), isStarred: true)
    let recentUnstarred = makeArticle(id: "recent-unstarred", fetchedAt: now.addingTimeInterval(-2 * 86_400))

    context.insert(oldUnstarred)
    context.insert(oldStarred)
    context.insert(recentUnstarred)
    try context.save()

    let result = try RetentionEngine().cleanup(context: context, retentionDays: 7, now: now)

    let remainingIDs = try context.fetch(FetchDescriptor<Article>()).map(\.id).sorted()
    #expect(result.deletedCount == 1)
    #expect(result.lastCleanupAt == now)
    #expect(remainingIDs == ["old-starred", "recent-unstarred"])
}

@MainActor
@Test func retentionDoesNotDeleteArticlesAtCutoff() throws {
    let container = try testContainer()
    let context = container.mainContext
    let now = Date(timeIntervalSince1970: 1_717_200_000)
    let cutoffArticle = makeArticle(id: "cutoff", fetchedAt: now.addingTimeInterval(-7 * 86_400))

    context.insert(cutoffArticle)
    try context.save()

    let result = try RetentionEngine().cleanup(context: context, retentionDays: 7, now: now)

    #expect(result.deletedCount == 0)
    #expect(try context.fetch(FetchDescriptor<Article>()).map(\.id) == ["cutoff"])
}

@MainActor
private func testContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Source.self, Article.self, AppSettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func makeArticle(
    id: String,
    fetchedAt: Date,
    isStarred: Bool = false
) -> Article {
    Article(
        id: id,
        sourceID: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
        sourceTitle: "Example",
        title: id,
        url: URL(string: "https://example.com/\(id)")!,
        fetchedAt: fetchedAt,
        isStarred: isStarred
    )
}
