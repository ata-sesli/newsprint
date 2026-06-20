import Foundation
import SwiftData

public struct SourceRefreshSummary: Sendable, Equatable {
    public let sourceID: UUID
    public let lane: SourceRefreshLane?
    public let insertedCount: Int
    public let skippedCount: Int
    public let insertedArticleIDs: [String]
    public let failed: Bool
    public let errorMessage: String?
    public let notModified: Bool

    public init(
        sourceID: UUID,
        lane: SourceRefreshLane? = nil,
        insertedCount: Int = 0,
        skippedCount: Int = 0,
        insertedArticleIDs: [String] = [],
        failed: Bool = false,
        errorMessage: String? = nil,
        notModified: Bool = false
    ) {
        self.sourceID = sourceID
        self.lane = lane
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
    public let sourceIDs: [UUID]
    public let insertedCount: Int
    public let skippedCount: Int
    public let insertedArticleIDs: [String]
    public let failedCount: Int
    public let failedSourceIDs: [UUID]
    public let retentionDeletedCount: Int
    public let hnInsertedCount: Int
    public let otherInsertedCount: Int
    public let fastInsertedCount: Int
    public let recoveryInsertedCount: Int
    public let recoveredSourceCount: Int
    public let deadSourceCount: Int
    public let phaseTimings: [FeedRefreshPhaseTiming]

    public init(
        refreshedSourceCount: Int = 0,
        sourceIDs: [UUID] = [],
        insertedCount: Int = 0,
        skippedCount: Int = 0,
        insertedArticleIDs: [String] = [],
        failedCount: Int = 0,
        failedSourceIDs: [UUID] = [],
        retentionDeletedCount: Int = 0,
        hnInsertedCount: Int = 0,
        otherInsertedCount: Int = 0,
        fastInsertedCount: Int = 0,
        recoveryInsertedCount: Int = 0,
        recoveredSourceCount: Int = 0,
        deadSourceCount: Int = 0,
        phaseTimings: [FeedRefreshPhaseTiming] = []
    ) {
        self.refreshedSourceCount = refreshedSourceCount
        self.sourceIDs = sourceIDs
        self.insertedCount = insertedCount
        self.skippedCount = skippedCount
        self.insertedArticleIDs = insertedArticleIDs
        self.failedCount = failedCount
        self.failedSourceIDs = failedSourceIDs
        self.retentionDeletedCount = retentionDeletedCount
        self.hnInsertedCount = hnInsertedCount
        self.otherInsertedCount = otherInsertedCount
        self.fastInsertedCount = fastInsertedCount
        self.recoveryInsertedCount = recoveryInsertedCount
        self.recoveredSourceCount = recoveredSourceCount
        self.deadSourceCount = deadSourceCount
        self.phaseTimings = phaseTimings
    }
}

public enum SourceRefreshLane: String, Codable, Sendable, Equatable {
    case fast
    case recovery

    public var timeout: TimeInterval {
        switch self {
        case .fast:
            FeedHTTPClient.fastSourceRefreshTimeout
        case .recovery:
            FeedHTTPClient.recoverySourceRefreshTimeout
        }
    }
}

public enum SourceRefreshHealth: String, Codable, Sendable, Equatable {
    case healthy
    case degraded
    case dead
}

public enum RefreshProgressPhase: String, Codable, Sendable, Equatable {
    case fastFetching
    case recoveryFetching
    case preparing
}

public struct RefreshProgressState: Sendable, Equatable {
    public let phase: RefreshProgressPhase
    public let completedSourceCount: Int
    public let totalSourceCount: Int
    public let failedSourceCount: Int
    public let insertedCount: Int

    public init(
        phase: RefreshProgressPhase,
        completedSourceCount: Int,
        totalSourceCount: Int,
        failedSourceCount: Int = 0,
        insertedCount: Int = 0
    ) {
        self.phase = phase
        self.completedSourceCount = completedSourceCount
        self.totalSourceCount = totalSourceCount
        self.failedSourceCount = failedSourceCount
        self.insertedCount = insertedCount
    }

    public var displayText: String {
        switch phase {
        case .fastFetching:
            "Fast refresh \(completedSourceCount) / \(totalSourceCount)"
        case .recoveryFetching:
            "Recovery \(completedSourceCount) / \(totalSourceCount)"
        case .preparing:
            "Preparing feed"
        }
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

public extension FeedRefreshSummary {
    func merging(_ other: FeedRefreshSummary) -> FeedRefreshSummary {
        FeedRefreshSummary(
            refreshedSourceCount: refreshedSourceCount + other.refreshedSourceCount,
            sourceIDs: sourceIDs + other.sourceIDs,
            insertedCount: insertedCount + other.insertedCount,
            skippedCount: skippedCount + other.skippedCount,
            insertedArticleIDs: insertedArticleIDs + other.insertedArticleIDs,
            failedCount: failedCount + other.failedCount,
            failedSourceIDs: failedSourceIDs + other.failedSourceIDs,
            retentionDeletedCount: retentionDeletedCount + other.retentionDeletedCount,
            hnInsertedCount: hnInsertedCount + other.hnInsertedCount,
            otherInsertedCount: otherInsertedCount + other.otherInsertedCount,
            fastInsertedCount: fastInsertedCount + other.fastInsertedCount,
            recoveryInsertedCount: recoveryInsertedCount + other.recoveryInsertedCount,
            recoveredSourceCount: recoveredSourceCount + other.recoveredSourceCount,
            deadSourceCount: max(deadSourceCount, other.deadSourceCount),
            phaseTimings: phaseTimings + other.phaseTimings
        )
    }

    var sourceIDsSucceededOrNotModified: Set<UUID> {
        Set(sourceIDs).subtracting(failedSourceIDs)
    }
}

private struct SourceRefreshPayload: Sendable {
    let source: SourceSnapshot
    let phase: RefreshPriorityPhase
    let lane: SourceRefreshLane
    let outcome: SourceRefreshOutcome
    let elapsedMilliseconds: Double
}

private enum SourceRefreshOutcome: Sendable {
    case notModified(FeedHTTPResponse)
    case drafts([ArticleDraft], response: FeedHTTPResponse?)
    case failure(String)
}

private actor RefreshProgressReporter {
    private let phase: RefreshProgressPhase
    private let totalSourceCount: Int
    private let progressHandler: (@Sendable (RefreshProgressState) async -> Void)?

    private var completedSourceCount = 0
    private var failedSourceCount = 0
    private var insertedCount = 0

    init(
        phase: RefreshProgressPhase,
        totalSourceCount: Int,
        progressHandler: (@Sendable (RefreshProgressState) async -> Void)?
    ) {
        self.phase = phase
        self.totalSourceCount = totalSourceCount
        self.progressHandler = progressHandler
    }

    func start() async {
        await progressHandler?(RefreshProgressState(
            phase: phase,
            completedSourceCount: completedSourceCount,
            totalSourceCount: totalSourceCount
        ))
    }

    func report(_ summary: SourceRefreshSummary) async {
        completedSourceCount += 1
        failedSourceCount += summary.failed ? 1 : 0
        insertedCount += summary.insertedCount
        await progressHandler?(RefreshProgressState(
            phase: phase,
            completedSourceCount: completedSourceCount,
            totalSourceCount: totalSourceCount,
            failedSourceCount: failedSourceCount,
            insertedCount: insertedCount
        ))
    }
}

private extension SourceSnapshot {
    var refreshHealth: SourceRefreshHealth {
        if consecutiveFailureCount >= 3 {
            return .dead
        }
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            return .degraded
        }
        return .healthy
    }
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
        progressHandler: (@Sendable (RefreshProgressState) async -> Void)? = nil
    ) async -> FeedRefreshSummary {
        let fastSummary = await refreshFast(progressHandler: progressHandler)
        let recoverySummary = await refreshRecovery(
            excludingSourceIDs: fastSummary.sourceIDsSucceededOrNotModified,
            progressHandler: progressHandler
        )
        return fastSummary.merging(recoverySummary)
    }

    public func refreshFast(
        progressHandler: (@Sendable (RefreshProgressState) async -> Void)? = nil
    ) async -> FeedRefreshSummary {
        await refresh(lane: .fast, progressHandler: progressHandler)
    }

    public func refreshRecovery(
        excludingSourceIDs: Set<UUID> = [],
        progressHandler: (@Sendable (RefreshProgressState) async -> Void)? = nil
    ) async -> FeedRefreshSummary {
        await refresh(
            lane: .recovery,
            excludingSourceIDs: excludingSourceIDs,
            progressHandler: progressHandler
        )
    }

    private func refresh(
        lane: SourceRefreshLane,
        excludingSourceIDs: Set<UUID> = [],
        progressHandler: (@Sendable (RefreshProgressState) async -> Void)? = nil
    ) async -> FeedRefreshSummary {
        let startedAt = Date()
        do {
            let sources = try enabledSources()
            let sourceSnapshots = sources.map(SourceSnapshot.init(source:))
            let laneSources = sourceSnapshots.filter { snapshot in
                guard !excludingSourceIDs.contains(snapshot.id) else {
                    return false
                }
                switch lane {
                case .fast:
                    return snapshot.refreshHealth == .healthy
                case .recovery:
                    return snapshot.refreshHealth == .degraded
                }
            }
            let deadSourceCount = sourceSnapshots.filter { $0.refreshHealth == .dead }.count

            guard !laneSources.isEmpty else {
                await progressHandler?(RefreshProgressState(
                    phase: lane == .fast ? .fastFetching : .recoveryFetching,
                    completedSourceCount: 0,
                    totalSourceCount: 0
                ))
                let retentionDeletedCount = lane == .fast ? ((try? runRetentionCleanup()) ?? 0) : 0
                return FeedRefreshSummary(
                    retentionDeletedCount: retentionDeletedCount,
                    deadSourceCount: deadSourceCount
                )
            }

            let rules = try enabledRuleDefinitions()
            NewsprintLog.feed.info("Refresh lane started: lane=\(lane.rawValue, privacy: .public), sources=\(laneSources.count), dead=\(deadSourceCount), rules=\(rules.count)")

            var sourceSummaries: [SourceRefreshSummary] = []
            var phaseTimings: [FeedRefreshPhaseTiming] = []

            let laneResult = await refreshLane(
                laneSources,
                lane: lane,
                rules: rules,
                progressHandler: progressHandler
            )
            sourceSummaries.append(contentsOf: laneResult.summaries)
            phaseTimings.append(contentsOf: laneResult.timings)

            let retentionStartedAt = Date()
            let retentionDeletedCount = (try? runRetentionCleanup()) ?? 0
            let hnInsertedCount = sourceSummaries
                .filter { summary in sourceSnapshots.contains { $0.id == summary.sourceID && $0.kind == .hackerNews } }
                .reduce(0) { $0 + $1.insertedCount }
            let otherInsertedCount = sourceSummaries
                .filter { summary in sourceSnapshots.contains { $0.id == summary.sourceID && $0.kind != .hackerNews } }
                .reduce(0) { $0 + $1.insertedCount }
            let fastInsertedCount = sourceSummaries
                .filter { $0.lane == .fast }
                .reduce(0) { $0 + $1.insertedCount }
            let recoveryInsertedCount = sourceSummaries
                .filter { $0.lane == .recovery }
                .reduce(0) { $0 + $1.insertedCount }
            let recoveredSourceCount = sourceSummaries
                .filter { $0.lane == .recovery && !$0.failed }
                .count
            let summary = FeedRefreshSummary(
                refreshedSourceCount: sourceSummaries.filter { !$0.failed }.count,
                sourceIDs: sourceSummaries.map(\.sourceID),
                insertedCount: sourceSummaries.reduce(0) { $0 + $1.insertedCount },
                skippedCount: sourceSummaries.reduce(0) { $0 + $1.skippedCount },
                insertedArticleIDs: sourceSummaries.flatMap(\.insertedArticleIDs),
                failedCount: sourceSummaries.filter(\.failed).count,
                failedSourceIDs: sourceSummaries.filter(\.failed).map(\.sourceID),
                retentionDeletedCount: retentionDeletedCount,
                hnInsertedCount: hnInsertedCount,
                otherInsertedCount: otherInsertedCount,
                fastInsertedCount: fastInsertedCount,
                recoveryInsertedCount: recoveryInsertedCount,
                recoveredSourceCount: recoveredSourceCount,
                deadSourceCount: deadSourceCount,
                phaseTimings: phaseTimings
            )
            NewsprintLog.feed.info(
                "Refresh lane finished: lane=\(lane.rawValue, privacy: .public), refreshed=\(summary.refreshedSourceCount), failed=\(summary.failedCount), dead=\(summary.deadSourceCount), inserted=\(summary.insertedCount), fastInserted=\(summary.fastInsertedCount), recoveryInserted=\(summary.recoveryInsertedCount), hnInserted=\(summary.hnInsertedCount), otherInserted=\(summary.otherInsertedCount), skipped=\(summary.skippedCount), retentionDeleted=\(summary.retentionDeletedCount), retention=\(self.elapsedMilliseconds(since: retentionStartedAt), format: .fixed(precision: 1))ms, total=\(self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 1))ms"
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
                lane: .recovery,
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

    private func refreshLane(
        _ sources: [SourceSnapshot],
        lane: SourceRefreshLane,
        rules: [RuleDefinition],
        progressHandler: (@Sendable (RefreshProgressState) async -> Void)?
    ) async -> (summaries: [SourceRefreshSummary], timings: [FeedRefreshPhaseTiming]) {
        let total = sources.count
        let progressPhase: RefreshProgressPhase = lane == .fast ? .fastFetching : .recoveryFetching
        let progressReporter = RefreshProgressReporter(
            phase: progressPhase,
            totalSourceCount: total,
            progressHandler: progressHandler
        )
        await progressReporter.start()

        var summaries: [SourceRefreshSummary] = []
        var timings: [FeedRefreshPhaseTiming] = []

        let hackerNewsSources = sources.filter { $0.kind == .hackerNews }
        let otherSources = sources.filter { $0.kind != .hackerNews }

        if !hackerNewsSources.isEmpty {
            let phaseResult = await refreshPhase(
                hackerNewsSources,
                phase: .hackerNews,
                lane: lane,
                concurrency: Self.hackerNewsSourceConcurrency,
                rules: rules,
                progressReporter: progressReporter
            )
            summaries.append(contentsOf: phaseResult.summaries)
            timings.append(phaseResult.timing)
        }

        if !otherSources.isEmpty {
            let phaseResult = await refreshPhase(
                otherSources,
                phase: .otherSources,
                lane: lane,
                concurrency: Self.otherSourceConcurrency,
                rules: rules,
                progressReporter: progressReporter
            )
            summaries.append(contentsOf: phaseResult.summaries)
            timings.append(phaseResult.timing)
        }

        return (summaries, timings)
    }

    private func refreshPhase(
        _ sources: [SourceSnapshot],
        phase: RefreshPriorityPhase,
        lane: SourceRefreshLane,
        concurrency: Int,
        rules: [RuleDefinition],
        progressReporter: RefreshProgressReporter?
    ) async -> (summaries: [SourceRefreshSummary], timing: FeedRefreshPhaseTiming) {
        let startedAt = Date()
        NewsprintLog.feed.info("Refresh phase started: lane=\(lane.rawValue, privacy: .public), phase=\(phase.rawValue, privacy: .public), sources=\(sources.count), concurrency=\(concurrency), timeout=\(lane.timeout, format: .fixed(precision: 1))s")
        let httpClient = httpClient
        let hackerNewsClient = hackerNewsClient
        var summaries: [SourceRefreshSummary] = []

        await withTaskGroup(of: (Int, SourceRefreshPayload).self) { group in
            let taskLimit = min(max(concurrency, 1), sources.count)
            guard taskLimit > 0 else { return }

            var nextIndex = 0
            for _ in 0..<taskLimit {
                let index = nextIndex
                nextIndex += 1
                group.addTask {
                    (index, await Self.fetchSourcePayload(
                        source: sources[index],
                        phase: phase,
                        lane: lane,
                        httpClient: httpClient,
                        hackerNewsClient: hackerNewsClient
                    ))
                }
            }

            while let (_, payload) = await group.next() {
                let summary: SourceRefreshSummary
                do {
                    summary = try apply(payload: payload, rules: rules)
                } catch {
                    summary = SourceRefreshSummary(
                        sourceID: payload.source.id,
                        lane: lane,
                        failed: true,
                        errorMessage: SourceErrorFormatter.message(for: error)
                    )
                }
                summaries.append(summary)
                await progressReporter?.report(summary)

                if nextIndex < sources.count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        (index, await Self.fetchSourcePayload(
                            source: sources[index],
                            phase: phase,
                            lane: lane,
                            httpClient: httpClient,
                            hackerNewsClient: hackerNewsClient
                        ))
                    }
                }
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
            "Refresh phase finished: lane=\(lane.rawValue, privacy: .public), phase=\(phase.rawValue, privacy: .public), sources=\(timing.sourceCount), inserted=\(timing.insertedCount), failed=\(timing.failedCount), elapsed=\(timing.elapsedMilliseconds, format: .fixed(precision: 1))ms"
        )
        return (summaries, timing)
    }

    private static func fetchSourcePayload(
        source: SourceSnapshot,
        phase: RefreshPriorityPhase,
        lane: SourceRefreshLane,
        httpClient: FeedHTTPClient,
        hackerNewsClient: HackerNewsAPIClient
    ) async -> SourceRefreshPayload {
        let startedAt = Date()
        do {
            if source.kind == .hackerNews {
                let drafts = try await hackerNewsClient.fetchDrafts(for: source, timeout: lane.timeout)
                return SourceRefreshPayload(
                    source: source,
                    phase: phase,
                    lane: lane,
                    outcome: .drafts(drafts, response: nil),
                    elapsedMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
                )
            }

            let response = try await httpClient.fetch(source: source, timeout: lane.timeout)
            if response.isNotModified {
                return SourceRefreshPayload(
                    source: source,
                    phase: phase,
                    lane: lane,
                    outcome: .notModified(response),
                    elapsedMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
                )
            }

            let drafts = try FeedParser().parse(data: response.data, source: source)
            return SourceRefreshPayload(
                source: source,
                phase: phase,
                lane: lane,
                outcome: .drafts(drafts, response: response),
                elapsedMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            )
        } catch {
            return SourceRefreshPayload(
                source: source,
                phase: phase,
                lane: lane,
                outcome: .failure(SourceErrorFormatter.message(for: error)),
                elapsedMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            )
        }
    }

    private func apply(payload: SourceRefreshPayload, rules: [RuleDefinition]) throws -> SourceRefreshSummary {
        guard let source = try source(id: payload.source.id) else {
            return SourceRefreshSummary(
                sourceID: payload.source.id,
                lane: payload.lane,
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
            source.consecutiveFailureCount += 1
            try modelContext.save()
            NewsprintLog.feed.error("Source refresh failed off-main: \(source.title, privacy: .public), phase=\(payload.phase.rawValue, privacy: .public), \(message, privacy: .public), fetchParse=\(payload.elapsedMilliseconds, format: .fixed(precision: 1))ms")
            return SourceRefreshSummary(
                sourceID: source.id,
                lane: payload.lane,
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
            return SourceRefreshSummary(sourceID: source.id, lane: payload.lane, notModified: true)

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
                source.consecutiveFailureCount = 0
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
                lane: payload.lane,
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
        source.consecutiveFailureCount = 0
        source.etag = response.etag ?? source.etag
        source.lastModified = response.lastModified ?? source.lastModified
        source.updatedAt = date
    }

    private func elapsedMilliseconds(since start: Date) -> Double {
        Date().timeIntervalSince(start) * 1_000
    }
}
