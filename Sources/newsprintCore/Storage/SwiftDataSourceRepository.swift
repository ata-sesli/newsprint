import Foundation
import SwiftData

@MainActor
public final class SwiftDataSourceRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func enabledSources() throws -> [Source] {
        let descriptor = FetchDescriptor<Source>(
            predicate: #Predicate<Source> { source in
                source.enabled
            },
            sortBy: [SortDescriptor(\Source.title)]
        )
        return try context.fetch(descriptor)
    }

    public func save(_ source: Source) throws {
        source.updatedAt = Date()
        context.insert(source)
        try context.save()
    }

    @discardableResult
    public func saveIfNew(_ source: Source) throws -> Bool {
        guard try !exists(feedURL: source.url) else {
            return false
        }
        try save(source)
        return true
    }

    public func exists(feedURL: URL) throws -> Bool {
        let canonical = URLCanonicalizer.canonicalize(feedURL).absoluteString
        let descriptor = FetchDescriptor<Source>()
        return try context.fetch(descriptor).contains { source in
            URLCanonicalizer.canonicalize(source.url).absoluteString == canonical
        }
    }

    public func update(_ source: Source, title: String, category: String?, enabled: Bool) throws {
        source.title = title
        source.category = category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        source.enabled = enabled
        source.updatedAt = Date()
        try context.save()
    }

    public func delete(_ source: Source) throws {
        let sourceID = source.id
        let articleDescriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.sourceID == sourceID
            }
        )
        for article in try context.fetch(articleDescriptor) {
            context.delete(article)
        }
        context.delete(source)
        try context.save()
    }

    public func markFetchStarted(_ source: Source, at date: Date = Date()) throws {
        source.lastFetchedAt = date
        source.updatedAt = date
        try context.save()
    }

    public func markFetchSucceeded(_ source: Source, response: FeedHTTPResponse, at date: Date = Date()) throws {
        source.lastFetchedAt = date
        source.lastSuccessfulFetchAt = date
        source.lastErrorMessage = nil
        source.etag = response.etag ?? source.etag
        source.lastModified = response.lastModified ?? source.lastModified
        source.updatedAt = date
        try context.save()
    }

    public func markFetchFailed(_ source: Source, message: String, at date: Date = Date()) throws {
        source.lastFetchedAt = date
        source.lastErrorMessage = message
        source.updatedAt = date
        try context.save()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
