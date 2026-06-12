import Foundation
import SwiftData
import Testing
@testable import newsprintCore

@MainActor
@Test func sourceRepositorySkipsDuplicateCanonicalFeedURLs() throws {
    let container = try ModelContainer(
        for: Source.self, Article.self, AppSettings.self, FilterRule.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let repository = SwiftDataSourceRepository(context: context)
    let first = Source(title: "Example", url: URL(string: "https://example.com/feed.xml?utm_source=x")!)
    let duplicate = Source(title: "Example Duplicate", url: URL(string: "https://example.com/feed.xml")!)

    #expect(try repository.saveIfNew(first))
    #expect(try !repository.saveIfNew(duplicate))
    #expect(try context.fetch(FetchDescriptor<Source>()).count == 1)
}

@MainActor
@Test func sourceRepositoryDeletesSourceAndItsArticles() throws {
    let container = try ModelContainer(
        for: Source.self, Article.self, AppSettings.self, FilterRule.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let repository = SwiftDataSourceRepository(context: context)
    let source = Source(title: "Example", url: URL(string: "https://example.com/feed.xml")!)
    let article = Article(
        id: "article",
        sourceID: source.id,
        sourceTitle: source.title,
        title: "Article",
        url: URL(string: "https://example.com/article")!
    )
    context.insert(source)
    context.insert(article)
    try context.save()

    try repository.delete(source)

    #expect(try context.fetch(FetchDescriptor<Source>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<Article>()).isEmpty)
}

