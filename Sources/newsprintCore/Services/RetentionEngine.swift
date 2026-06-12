import Foundation
import SwiftData

public struct RetentionCleanupResult: Equatable, Sendable {
    public let deletedCount: Int
    public let lastCleanupAt: Date

    public init(deletedCount: Int, lastCleanupAt: Date) {
        self.deletedCount = deletedCount
        self.lastCleanupAt = lastCleanupAt
    }
}

@MainActor
public struct RetentionEngine {
    public init() {}

    public func cleanup(
        context: ModelContext,
        retentionDays: Int,
        now: Date = Date()
    ) throws -> RetentionCleanupResult {
        let clampedDays = min(max(retentionDays, 1), 365)
        let cutoff = Calendar.current.date(byAdding: .day, value: -clampedDays, to: now) ?? now
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                !article.isStarred && article.fetchedAt < cutoff
            }
        )
        let articles = try context.fetch(descriptor)

        for article in articles {
            context.delete(article)
        }

        try context.save()
        return RetentionCleanupResult(deletedCount: articles.count, lastCleanupAt: now)
    }
}

