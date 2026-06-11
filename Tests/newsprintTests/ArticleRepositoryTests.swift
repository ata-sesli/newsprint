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

