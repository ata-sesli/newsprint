import Foundation
import SwiftData

public struct SourceRefreshSummary: Sendable, Equatable {
    public let sourceID: UUID
    public let insertedCount: Int
    public let skippedCount: Int
    public let insertedArticleIDs: [String]
    public let failed: Bool
    public let errorMessage: String?
    public let notModified: Bool

    public init(
        sourceID: UUID,
        insertedCount: Int = 0,
        skippedCount: Int = 0,
        insertedArticleIDs: [String] = [],
        failed: Bool = false,
        errorMessage: String? = nil,
        notModified: Bool = false
    ) {
        self.sourceID = sourceID
        self.insertedCount = insertedCount
        self.skippedCount = skippedCount
        self.insertedArticleIDs = insertedArticleIDs
        self.failed = failed
        self.errorMessage = errorMessage
        self.notModified = notModified
    }
}

public struct FeedRefreshSummary: Sendable, Equatable {
    public let refreshedSourceCount: Int
    public let insertedCount: Int
    public let skippedCount: Int
    public let insertedArticleIDs: [String]
    public let failedCount: Int
    public let retentionDeletedCount: Int

    public init(
        refreshedSourceCount: Int = 0,
        insertedCount: Int = 0,
        skippedCount: Int = 0,
        insertedArticleIDs: [String] = [],
        failedCount: Int = 0,
        retentionDeletedCount: Int = 0
    ) {
        self.refreshedSourceCount = refreshedSourceCount
        self.insertedCount = insertedCount
        self.skippedCount = skippedCount
        self.insertedArticleIDs = insertedArticleIDs
        self.failedCount = failedCount
        self.retentionDeletedCount = retentionDeletedCount
    }
}

public actor FeedRefreshActor: ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor
    private let httpClient: FeedHTTPClient

    public init(modelContainer: ModelContainer, httpClient: FeedHTTPClient = FeedHTTPClient()) {
        let modelContext = ModelContext(modelContainer)
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.httpClient = httpClient
    }

    public func refreshAll() async -> FeedRefreshSummary {
        do {
            let sources = try enabledSources()
            let rules = try enabledRuleDefinitions()
            var sourceSummaries: [SourceRefreshSummary] = []
            for source in sources {
                sourceSummaries.append(await refresh(source: source, rules: rules))
            }
            let retentionDeletedCount = (try? runRetentionCleanup()) ?? 0
            return FeedRefreshSummary(
                refreshedSourceCount: sourceSummaries.filter { !$0.failed }.count,
                insertedCount: sourceSummaries.reduce(0) { $0 + $1.insertedCount },
                skippedCount: sourceSummaries.reduce(0) { $0 + $1.skippedCount },
                insertedArticleIDs: sourceSummaries.flatMap(\.insertedArticleIDs),
                failedCount: sourceSummaries.filter(\.failed).count,
                retentionDeletedCount: retentionDeletedCount
            )
        } catch {
            return FeedRefreshSummary(failedCount: 1)
        }
    }

    public func refresh(sourceID: UUID) async -> SourceRefreshSummary {
        do {
            guard let source = try source(id: sourceID) else {
                return SourceRefreshSummary(
                    sourceID: sourceID,
                    failed: true,
                    errorMessage: "Source not found"
                )
            }
            let summary = await refresh(source: source, rules: try enabledRuleDefinitions())
            _ = try? runRetentionCleanup()
            return summary
        } catch {
            return SourceRefreshSummary(
                sourceID: sourceID,
                failed: true,
                errorMessage: SourceErrorFormatter.message(for: error)
            )
        }
    }

    private func refresh(source: Source, rules: [RuleDefinition]) async -> SourceRefreshSummary {
        let now = Date()
        source.lastFetchedAt = now
        source.updatedAt = now
        let snapshot = SourceSnapshot(source: source)

        do {
            NewsprintLog.feed.info("Refreshing source off-main: \(source.title, privacy: .public)")
            let response = try await httpClient.fetch(source: snapshot)

            if response.isNotModified {
                markFetchSucceeded(source, response: response, at: Date())
                try modelContext.save()
                return SourceRefreshSummary(sourceID: source.id, notModified: true)
            }

            let drafts = try FeedParser().parse(data: response.data, source: snapshot)
            let articles = drafts.map { draft in
                Article(
                    draft: draft,
                    ruleResult: RuleEngine().apply(rules: rules, to: draft)
                )
            }
            let insertResult = try insertNewArticles(articles)
            markFetchSucceeded(source, response: response, at: Date())
            try modelContext.save()
            NewsprintLog.feed.info("Source refreshed off-main: \(source.title, privacy: .public), drafts: \(drafts.count), inserted: \(insertResult.insertedCount), skipped: \(insertResult.skippedCount)")
            return SourceRefreshSummary(
                sourceID: source.id,
                insertedCount: insertResult.insertedCount,
                skippedCount: insertResult.skippedCount,
                insertedArticleIDs: insertResult.insertedArticleIDs
            )
        } catch {
            let message = SourceErrorFormatter.message(for: error)
            NewsprintLog.feed.error("Source refresh failed off-main: \(source.title, privacy: .public), \(message, privacy: .public)")
            source.lastFetchedAt = Date()
            source.lastErrorMessage = message
            source.updatedAt = Date()
            try? modelContext.save()
            return SourceRefreshSummary(
                sourceID: source.id,
                failed: true,
                errorMessage: message
            )
        }
    }

    private func enabledSources() throws -> [Source] {
        let descriptor = FetchDescriptor<Source>(
            predicate: #Predicate<Source> { source in
                source.enabled
            },
            sortBy: [SortDescriptor(\Source.title)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func source(id sourceID: UUID) throws -> Source? {
        var descriptor = FetchDescriptor<Source>(
            predicate: #Predicate<Source> { source in
                source.id == sourceID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func enabledRuleDefinitions() throws -> [RuleDefinition] {
        let descriptor = FetchDescriptor<FilterRule>(
            predicate: #Predicate<FilterRule> { rule in
                rule.enabled
            },
            sortBy: [SortDescriptor(\FilterRule.priority), SortDescriptor(\FilterRule.createdAt)]
        )
        return try modelContext.fetch(descriptor).map(RuleDefinition.init(rule:))
    }

    private func insertNewArticles(_ articles: [Article]) throws -> ArticleBatchInsertResult {
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
        let existingIDs = Set(try modelContext.fetch(descriptor).map(\.id))
        var seenIDs = Set<String>()
        var insertedArticleIDs: [String] = []
        var insertedCount = 0
        var skippedCount = 0

        for article in articles {
            guard !existingIDs.contains(article.id),
                  !seenIDs.contains(article.id) else {
                skippedCount += 1
                continue
            }
            modelContext.insert(article)
            seenIDs.insert(article.id)
            insertedArticleIDs.append(article.id)
            insertedCount += 1
        }

        return ArticleBatchInsertResult(
            insertedCount: insertedCount,
            skippedCount: skippedCount,
            insertedArticleIDs: insertedArticleIDs
        )
    }

    private func runRetentionCleanup(now: Date = Date()) throws -> Int {
        let settings = try loadOrCreateSettings()
        let clampedDays = min(max(settings.retentionDays, 1), 365)
        let cutoff = Calendar.current.date(byAdding: .day, value: -clampedDays, to: now) ?? now
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                !article.isStarred && article.fetchedAt < cutoff
            }
        )
        let articles = try modelContext.fetch(descriptor)
        for article in articles {
            modelContext.delete(article)
        }
        settings.lastRetentionCleanupAt = now
        settings.lastRetentionDeletedCount = articles.count
        try modelContext.save()
        return articles.count
    }

    private func loadOrCreateSettings() throws -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        if let settings = try modelContext.fetch(descriptor).first {
            return settings
        }
        let settings = AppSettings()
        modelContext.insert(settings)
        try modelContext.save()
        return settings
    }

    private func markFetchSucceeded(_ source: Source, response: FeedHTTPResponse, at date: Date) {
        source.lastFetchedAt = date
        source.lastSuccessfulFetchAt = date
        source.lastErrorMessage = nil
        source.etag = response.etag ?? source.etag
        source.lastModified = response.lastModified ?? source.lastModified
        source.updatedAt = date
    }
}
