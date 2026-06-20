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

@MainActor
@Test func sourceRepositoryDeletesMultipleSourcesAndTheirArticles() throws {
    let container = try ModelContainer(
        for: Source.self, Article.self, AppSettings.self, FilterRule.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let repository = SwiftDataSourceRepository(context: context)
    let first = Source(title: "First", url: URL(string: "https://example.com/first.xml")!)
    let second = Source(title: "Second", url: URL(string: "https://example.com/second.xml")!)
    let kept = Source(title: "Kept", url: URL(string: "https://example.com/kept.xml")!)
    let firstArticle = Article(
        id: "first-article",
        sourceID: first.id,
        sourceTitle: first.title,
        title: "First Article",
        url: URL(string: "https://example.com/first")!
    )
    let secondArticle = Article(
        id: "second-article",
        sourceID: second.id,
        sourceTitle: second.title,
        title: "Second Article",
        url: URL(string: "https://example.com/second")!
    )
    let keptArticle = Article(
        id: "kept-article",
        sourceID: kept.id,
        sourceTitle: kept.title,
        title: "Kept Article",
        url: URL(string: "https://example.com/kept")!
    )
    for model in [first, second, kept] {
        context.insert(model)
    }
    for model in [firstArticle, secondArticle, keptArticle] {
        context.insert(model)
    }
    try context.save()

    try repository.delete([first, second])

    let remainingSources = try context.fetch(FetchDescriptor<Source>())
    let remainingArticles = try context.fetch(FetchDescriptor<Article>())
    #expect(remainingSources.map(\.id) == [kept.id])
    #expect(remainingArticles.map(\.id) == ["kept-article"])
}
