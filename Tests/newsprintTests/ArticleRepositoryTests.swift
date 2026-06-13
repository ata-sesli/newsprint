import Testing
import Foundation
import SwiftData
@testable import newsprintCore

@MainActor
@Test func repositorySkipsDuplicateArticleIDs() throws {
    let container = try ModelContainer(
        for: Source.self, Article.self, AppSettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let repository = SwiftDataArticleRepository(context: context)
    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    let article = Article(
        id: "https://example.com/one",
        sourceID: sourceID,
        sourceTitle: "Example",
        title: "One",
        url: URL(string: "https://example.com/one")!
    )

    try repository.insertIfNew(article)
    try repository.insertIfNew(article)

    #expect(try repository.exists(articleID: article.id))
    #expect(try context.fetch(FetchDescriptor<Article>()).count == 1)
}

@MainActor
@Test func repositoryBatchInsertsOnlyNewArticleIDs() throws {
    let container = try ModelContainer(
        for: Source.self, Article.self, AppSettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let repository = SwiftDataArticleRepository(context: context)
    let existing = makeRepositoryArticle(id: "existing")
    try repository.insert(existing)

    let result = try repository.insertNewArticles([
        makeRepositoryArticle(id: "existing"),
        makeRepositoryArticle(id: "new-one"),
        makeRepositoryArticle(id: "new-two")
    ])

    let ids = try context.fetch(FetchDescriptor<Article>()).map(\.id).sorted()
    #expect(result.insertedCount == 2)
    #expect(result.skippedCount == 1)
    #expect(ids == ["existing", "new-one", "new-two"])
}

@MainActor
@Test func repositoryBatchSkipsDuplicateIDsInsideIncomingBatch() throws {
    let container = try ModelContainer(
        for: Source.self, Article.self, AppSettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let repository = SwiftDataArticleRepository(context: context)

    let result = try repository.insertNewArticles([
        makeRepositoryArticle(id: "same"),
        makeRepositoryArticle(id: "same"),
        makeRepositoryArticle(id: "other")
    ])

    let ids = try context.fetch(FetchDescriptor<Article>()).map(\.id).sorted()
    #expect(result.insertedCount == 2)
    #expect(result.skippedCount == 1)
    #expect(ids == ["other", "same"])
}

private func makeRepositoryArticle(id: String) -> Article {
    Article(
        id: id,
        sourceID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        sourceTitle: "Example",
        title: id,
        url: URL(string: "https://example.com/\(id)")!
    )
}
