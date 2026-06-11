import Foundation
import SwiftData

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

