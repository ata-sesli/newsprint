import Foundation
import SwiftData

@MainActor
public final class FeedRefreshService {
    private let context: ModelContext
    private let sourceRepository: SwiftDataSourceRepository
    private let articleRepository: SwiftDataArticleRepository
    private let httpClient: FeedHTTPClient
    private let parser: FeedParser

    public init(
        context: ModelContext,
        httpClient: FeedHTTPClient = FeedHTTPClient(),
        parser: FeedParser = FeedParser()
    ) {
        self.context = context
        self.sourceRepository = SwiftDataSourceRepository(context: context)
        self.articleRepository = SwiftDataArticleRepository(context: context)
        self.httpClient = httpClient
        self.parser = parser
    }

    public func refreshAll() async {
        do {
            let sources = try sourceRepository.enabledSources()
            for source in sources {
                await refresh(source: source, runRetention: false)
            }
            try runRetentionCleanup()
        } catch {
            // Source load failures are surfaced through individual source errors in the UI where possible.
        }
    }

    public func refresh(source: Source) async {
        await refresh(source: source, runRetention: true)
    }

    private func refresh(source: Source, runRetention: Bool) async {
        do {
            try sourceRepository.markFetchStarted(source)
            let response = try await httpClient.fetch(source: source)

            if response.isNotModified {
                try sourceRepository.markFetchSucceeded(source, response: response)
                if runRetention {
                    try runRetentionCleanup()
                }
                return
            }

            let drafts = try parser.parse(data: response.data, source: source)
            for draft in drafts {
                try articleRepository.insertIfNew(Article(draft: draft))
            }

            try sourceRepository.markFetchSucceeded(source, response: response)
            if runRetention {
                try runRetentionCleanup()
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            try? sourceRepository.markFetchFailed(source, message: message)
            if runRetention {
                try? runRetentionCleanup()
            }
        }
    }

    private func runRetentionCleanup() throws {
        let settings = try SettingsRepository.loadOrCreate(in: context)
        let result = try RetentionEngine().cleanup(
            context: context,
            retentionDays: settings.retentionDays
        )
        settings.lastRetentionCleanupAt = result.lastCleanupAt
        settings.lastRetentionDeletedCount = result.deletedCount
        try context.save()
    }
}
