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

