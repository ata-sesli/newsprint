import Foundation
import SwiftData

@MainActor
@available(*, deprecated, message: "Use FeedRefreshActor for UI and background refreshes.")
public final class FeedRefreshService {
    private let context: ModelContext
    private let sourceRepository: SwiftDataSourceRepository
    private let articleRepository: SwiftDataArticleRepository
    private let ruleRepository: SwiftDataRuleRepository
    private let httpClient: FeedHTTPClient
    private let parser: FeedParser
    private let ruleEngine: RuleEngine

    public init(
        context: ModelContext,
        httpClient: FeedHTTPClient = FeedHTTPClient(),
        parser: FeedParser = FeedParser()
    ) {
        self.context = context
        self.sourceRepository = SwiftDataSourceRepository(context: context)
        self.articleRepository = SwiftDataArticleRepository(context: context)
        self.ruleRepository = SwiftDataRuleRepository(context: context)
        self.httpClient = httpClient
        self.parser = parser
        self.ruleEngine = RuleEngine()
    }

    public func refreshAll() async {
        do {
            let sources = try sourceRepository.enabledSources()
            NewsprintLog.feed.info("Refreshing \(sources.count) sources")
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
            NewsprintLog.feed.info("Refreshing source: \(source.title, privacy: .public)")
            let snapshot = SourceSnapshot(source: source)
            let response = try await httpClient.fetch(source: snapshot)

            if response.isNotModified {
                try sourceRepository.markFetchSucceeded(source, response: response)
                if runRetention {
                    try runRetentionCleanup()
                }
                return
            }

            let drafts = try parser.parse(data: response.data, source: snapshot)
            let rules = try ruleRepository.enabledRules()
            let articles = drafts.map { draft in
                let result = ruleEngine.apply(rules: rules, to: draft)
                return Article(draft: draft, ruleResult: result)
            }
            let insertResult = try articleRepository.insertNewArticles(articles)

            try sourceRepository.markFetchSucceeded(source, response: response)
            NewsprintLog.feed.info("Source refreshed: \(source.title, privacy: .public), drafts: \(drafts.count), inserted: \(insertResult.insertedCount), skipped: \(insertResult.skippedCount)")
            if runRetention {
                try runRetentionCleanup()
            }
        } catch {
            let message = SourceErrorFormatter.message(for: error)
            NewsprintLog.feed.error("Source refresh failed: \(source.title, privacy: .public), \(message, privacy: .public)")
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
