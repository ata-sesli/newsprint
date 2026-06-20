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
    public let hnInsertedCount: Int
    public let otherInsertedCount: Int
    public let phaseTimings: [FeedRefreshPhaseTiming]

    public init(
        refreshedSourceCount: Int = 0,
        insertedCount: Int = 0,
        skippedCount: Int = 0,
        insertedArticleIDs: [String] = [],
        failedCount: Int = 0,
        retentionDeletedCount: Int = 0,
        hnInsertedCount: Int = 0,
        otherInsertedCount: Int = 0,
        phaseTimings: [FeedRefreshPhaseTiming] = []
    ) {
        self.refreshedSourceCount = refreshedSourceCount
        self.insertedCount = insertedCount
        self.skippedCount = skippedCount
        self.insertedArticleIDs = insertedArticleIDs
        self.failedCount = failedCount
        self.retentionDeletedCount = retentionDeletedCount
        self.hnInsertedCount = hnInsertedCount
        self.otherInsertedCount = otherInsertedCount
        self.phaseTimings = phaseTimings
    }
}

public enum RefreshPriorityPhase: String, Codable, Sendable, Equatable {
    case hackerNews
    case otherSources

    public var statusMessage: String {
        switch self {
        case .hackerNews:
            return "Refreshing Hacker News..."
        case .otherSources:
            return "Refreshing feeds..."
        }
    }
}

public struct FeedRefreshPhaseTiming: Sendable, Equatable {
    public let phase: RefreshPriorityPhase
    public let sourceCount: Int
    public let insertedCount: Int
    public let failedCount: Int
    public let elapsedMilliseconds: Double

    public init(
        phase: RefreshPriorityPhase,
        sourceCount: Int,
        insertedCount: Int,
        failedCount: Int,
        elapsedMilliseconds: Double
    ) {
        self.phase = phase
        self.sourceCount = sourceCount
        self.insertedCount = insertedCount
        self.failedCount = failedCount
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

private struct SourceRefreshPayload: Sendable {
    let source: SourceSnapshot
    let phase: RefreshPriorityPhase
    let outcome: SourceRefreshOutcome
    let elapsedMilliseconds: Double
}

private enum SourceRefreshOutcome: Sendable {
    case notModified(FeedHTTPResponse)
    case drafts([ArticleDraft], response: FeedHTTPResponse?)
    case failure(String)
}

public actor FeedRefreshActor: ModelActor {
    private static let hackerNewsSourceConcurrency = 3
    private static let otherSourceConcurrency = 50
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor
    private let httpClient: FeedHTTPClient
    private let hackerNewsClient: HackerNewsAPIClient

    public init(
        modelContainer: ModelContainer,
        httpClient: FeedHTTPClient = FeedHTTPClient(),
        hackerNewsClient: HackerNewsAPIClient? = nil
    ) {
        let modelContext = ModelContext(modelContainer)
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.httpClient = httpClient
        self.hackerNewsClient = hackerNewsClient ?? HackerNewsAPIClient(httpClient: httpClient)
    }

    public func refreshAll(
        phaseHandler: (@Sendable (RefreshPriorityPhase) async -> Void)? = nil
    ) async -> FeedRefreshSummary {
        let startedAt = Date()
        do {
            let sources = try enabledSources()
            let sourceSnapshots = sources.map(SourceSnapshot.init(source:))
            let hackerNewsSources = sourceSnapshots.filter { $0.kind == .hackerNews }
            let otherSources = sourceSnapshots.filter { $0.kind != .hackerNews }
            let rules = try enabledRuleDefinitions()
            NewsprintLog.feed.info("Refresh all started: sources=\(sources.count), hackerNews=\(hackerNewsSources.count), other=\(otherSources.count), rules=\(rules.count)")

            var sourceSummaries: [SourceRefreshSummary] = []
            var phaseTimings: [FeedRefreshPhaseTiming] = []

            if !hackerNewsSources.isEmpty {
                await phaseHandler?(.hackerNews)
                let phaseResult = await refreshPhase(
                    hackerNewsSources,
                    phase: .hackerNews,
                    concurrency: Self.hackerNewsSourceConcurrency,
                    rules: rules
                )
                sourceSummaries.append(contentsOf: phaseResult.summaries)
                phaseTimings.append(phaseResult.timing)
            }

            if !otherSources.isEmpty {
                await phaseHandler?(.otherSources)
                let phaseResult = await refreshPhase(
                    otherSources,
                    phase: .otherSources,
                    concurrency: Self.otherSourceConcurrency,
                    rules: rules
                )
                sourceSummaries.append(contentsOf: phaseResult.summaries)
                phaseTimings.append(phaseResult.timing)
            }

            let retentionStartedAt = Date()
            let retentionDeletedCount = (try? runRetentionCleanup()) ?? 0
            let hnInsertedCount = sourceSummaries
                .filter { summary in hackerNewsSources.contains { $0.id == summary.sourceID } }
                .reduce(0) { $0 + $1.insertedCount }
            let otherInsertedCount = sourceSummaries
                .filter { summary in otherSources.contains { $0.id == summary.sourceID } }
                .reduce(0) { $0 + $1.insertedCount }
            let summary = FeedRefreshSummary(
                refreshedSourceCount: sourceSummaries.filter { !$0.failed }.count,
                insertedCount: sourceSummaries.reduce(0) { $0 + $1.insertedCount },
                skippedCount: sourceSummaries.reduce(0) { $0 + $1.skippedCount },
                insertedArticleIDs: sourceSummaries.flatMap(\.insertedArticleIDs),
                failedCount: sourceSummaries.filter(\.failed).count,
                retentionDeletedCount: retentionDeletedCount,
                hnInsertedCount: hnInsertedCount,
                otherInsertedCount: otherInsertedCount,
                phaseTimings: phaseTimings
            )
            NewsprintLog.feed.info(
                "Refresh all finished: refreshed=\(summary.refreshedSourceCount), failed=\(summary.failedCount), inserted=\(summary.insertedCount), hnInserted=\(summary.hnInsertedCount), otherInserted=\(summary.otherInsertedCount), skipped=\(summary.skippedCount), retentionDeleted=\(summary.retentionDeletedCount), retention=\(self.elapsedMilliseconds(since: retentionStartedAt), format: .fixed(precision: 1))ms, total=\(self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 1))ms"
            )
            return summary
        } catch {
            NewsprintLog.feed.error("Refresh all failed before source refresh: \(SourceErrorFormatter.message(for: error), privacy: .public), total=\(self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 1))ms")
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
            let rules = try enabledRuleDefinitions()
            let snapshot = SourceSnapshot(source: source)
            let payload = await Self.fetchSourcePayload(
                source: snapshot,
                phase: source.kind == .hackerNews ? .hackerNews : .otherSources,
                httpClient: httpClient,
                hackerNewsClient: hackerNewsClient
            )
            let summary = try apply(payload: payload, rules: rules)
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

    private func refreshPhase(
        _ sources: [SourceSnapshot],
        phase: RefreshPriorityPhase,
        concurrency: Int,
        rules: [RuleDefinition]
    ) async -> (summaries: [SourceRefreshSummary], timing: FeedRefreshPhaseTiming) {
        let startedAt = Date()
        NewsprintLog.feed.info("Refresh phase started: phase=\(phase.rawValue, privacy: .public), sources=\(sources.count), concurrency=\(concurrency)")
        let httpClient = httpClient
        let hackerNewsClient = hackerNewsClient
        let payloads = await BoundedTaskGroup.map(sources, limit: concurrency) { source in
            await Self.fetchSourcePayload(
                source: source,
                phase: phase,
                httpClient: httpClient,
                hackerNewsClient: hackerNewsClient
            )
        }
        var summaries: [SourceRefreshSummary] = []
        for payload in payloads {
            do {
                summaries.append(try apply(payload: payload, rules: rules))
            } catch {
                summaries.append(SourceRefreshSummary(
                    sourceID: payload.source.id,
                    failed: true,
                    errorMessage: SourceErrorFormatter.message(for: error)
                ))
            }
        }
        let timing = FeedRefreshPhaseTiming(
            phase: phase,
            sourceCount: sources.count,
            insertedCount: summaries.reduce(0) { $0 + $1.insertedCount },
            failedCount: summaries.filter(\.failed).count,
            elapsedMilliseconds: elapsedMilliseconds(since: startedAt)
        )
        NewsprintLog.feed.info(
            "Refresh phase finished: phase=\(phase.rawValue, privacy: .public), sources=\(timing.sourceCount), inserted=\(timing.insertedCount), failed=\(timing.failedCount), elapsed=\(timing.elapsedMilliseconds, format: .fixed(precision: 1))ms"
        )
        return (summaries, timing)
    }

    private static func fetchSourcePayload(
        source: SourceSnapshot,
        phase: RefreshPriorityPhase,
        httpClient: FeedHTTPClient,
        hackerNewsClient: HackerNewsAPIClient
    ) async -> SourceRefreshPayload {
        let startedAt = Date()
        do {
            if source.kind == .hackerNews {
                let drafts = try await hackerNewsClient.fetchDrafts(for: source)
                return SourceRefreshPayload(
                    source: source,
                    phase: phase,
                    outcome: .drafts(drafts, response: nil),
                    elapsedMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
                )
            }

            let response = try await httpClient.fetch(source: source)
            if response.isNotModified {
                return SourceRefreshPayload(
                    source: source,
                    phase: phase,
                    outcome: .notModified(response),
                    elapsedMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
                )
            }

            let drafts = try FeedParser().parse(data: response.data, source: source)
            return SourceRefreshPayload(
                source: source,
                phase: phase,
                outcome: .drafts(drafts, response: response),
                elapsedMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            )
        } catch {
            return SourceRefreshPayload(
                source: source,
                phase: phase,
                outcome: .failure(SourceErrorFormatter.message(for: error)),
                elapsedMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            )
        }
    }

    private func apply(payload: SourceRefreshPayload, rules: [RuleDefinition]) throws -> SourceRefreshSummary {
        guard let source = try source(id: payload.source.id) else {
            return SourceRefreshSummary(
                sourceID: payload.source.id,
                failed: true,
                errorMessage: "Source not found"
            )
        }

        let now = Date()
        source.lastFetchedAt = now
        source.updatedAt = now

        switch payload.outcome {
        case .failure(let message):
            source.lastErrorMessage = message
            try modelContext.save()
            NewsprintLog.feed.error("Source refresh failed off-main: \(source.title, privacy: .public), phase=\(payload.phase.rawValue, privacy: .public), \(message, privacy: .public), fetchParse=\(payload.elapsedMilliseconds, format: .fixed(precision: 1))ms")
            return SourceRefreshSummary(
                sourceID: source.id,
                failed: true,
                errorMessage: message
            )

        case .notModified(let response):
            markFetchSucceeded(source, response: response, at: now)
            let saveStartedAt = Date()
            try modelContext.save()
            NewsprintLog.feed.info(
                "Source refresh finished: \(source.title, privacy: .public), phase=\(payload.phase.rawValue, privacy: .public), notModified=true, fetchParse=\(payload.elapsedMilliseconds, format: .fixed(precision: 1))ms, save=\(self.elapsedMilliseconds(since: saveStartedAt), format: .fixed(precision: 1))ms"
            )
            return SourceRefreshSummary(sourceID: source.id, notModified: true)

        case .drafts(let drafts, let response):
            let ruleStartedAt = Date()
            let articles = drafts.map { draft in
                Article(
                    draft: draft,
                    ruleResult: RuleEngine().apply(rules: rules, to: draft)
                )
            }
            let ruleMilliseconds = elapsedMilliseconds(since: ruleStartedAt)
            let insertStartedAt = Date()
            let insertResult = try insertNewArticles(articles)
            let insertMilliseconds = elapsedMilliseconds(since: insertStartedAt)

            if let response {
                markFetchSucceeded(source, response: response, at: now)
            } else {
                if let configuration = HackerNewsFeedURLBuilder.configuration(from: payload.source.url) {
                    source.url = HackerNewsFeedURLBuilder.url(for: configuration)
                }
                source.lastFetchedAt = now
                source.lastSuccessfulFetchAt = now
                source.lastErrorMessage = nil
                source.etag = nil
                source.lastModified = nil
                source.updatedAt = now
            }

            let saveStartedAt = Date()
            try modelContext.save()
            NewsprintLog.feed.info(
                "Source refresh finished: \(source.title, privacy: .public), phase=\(payload.phase.rawValue, privacy: .public), kind=\(source.kind.rawValue, privacy: .public), drafts=\(drafts.count), inserted=\(insertResult.insertedCount), skipped=\(insertResult.skippedCount), fetchParse=\(payload.elapsedMilliseconds, format: .fixed(precision: 1))ms, rules=\(ruleMilliseconds, format: .fixed(precision: 1))ms, insert=\(insertMilliseconds, format: .fixed(precision: 1))ms, save=\(self.elapsedMilliseconds(since: saveStartedAt), format: .fixed(precision: 1))ms"
            )
            return SourceRefreshSummary(
                sourceID: source.id,
                insertedCount: insertResult.insertedCount,
                skippedCount: insertResult.skippedCount,
                insertedArticleIDs: insertResult.insertedArticleIDs
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

    private func elapsedMilliseconds(since start: Date) -> Double {
        Date().timeIntervalSince(start) * 1_000
    }
}
