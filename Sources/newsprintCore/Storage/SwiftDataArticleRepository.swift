import Foundation
import SwiftData

public struct ArticleBatchInsertResult: Equatable, Sendable {
    public let insertedCount: Int
    public let skippedCount: Int

    public init(insertedCount: Int, skippedCount: Int) {
        self.insertedCount = insertedCount
        self.skippedCount = skippedCount
    }
}

@MainActor
public final class SwiftDataArticleRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func exists(articleID: String) throws -> Bool {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.id == articleID
            }
        )
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    public func insert(_ article: Article) throws {
        context.insert(article)
        try context.save()
    }

    @discardableResult
    public func insertIfNew(_ article: Article) throws -> Bool {
        guard try !exists(articleID: article.id) else {
            return false
        }
        context.insert(article)
        try context.save()
        return true
    }

    @discardableResult
    public func insertNewArticles(_ articles: [Article]) throws -> ArticleBatchInsertResult {
        let incomingIDs = Set(articles.map(\.id))
        guard !incomingIDs.isEmpty else {
            return ArticleBatchInsertResult(insertedCount: 0, skippedCount: 0)
        }

        let incomingIDList = Array(incomingIDs)
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                incomingIDList.contains(article.id)
            }
        )
        let existingIDs = Set(try context.fetch(descriptor).map(\.id))
        var seenIDs = Set<String>()
        var insertedCount = 0
        var skippedCount = 0

        for article in articles {
            guard !existingIDs.contains(article.id),
                  !seenIDs.contains(article.id) else {
                skippedCount += 1
                continue
            }

            context.insert(article)
            seenIDs.insert(article.id)
            insertedCount += 1
        }

        if insertedCount > 0 {
            try context.save()
        }

        return ArticleBatchInsertResult(insertedCount: insertedCount, skippedCount: skippedCount)
    }

    public func markRead(_ article: Article, read: Bool) throws {
        article.isRead = read
        try context.save()
    }

    public func star(_ article: Article, starred: Bool) throws {
        article.isStarred = starred
        try context.save()
    }

    public func hide(_ article: Article, hidden: Bool) throws {
        article.isHidden = hidden
        try context.save()
    }
}
