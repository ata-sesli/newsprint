import Foundation
import SwiftData
import Testing
@testable import newsprintCore

@MainActor
@Test func feedRefreshActorInsertsFixtureArticles() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    let feedURL = URL(string: "https://example.com/actor-insert-rss.xml")!
    let source = Source(title: "Example RSS", url: feedURL, kind: .rss)
    context.insert(source)
    try context.save()

    MockFeedURLProtocol.register(.success(try fixtureData("rss", extension: "xml")), for: feedURL)
    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    let summary = await actor.refreshAll()
    let articles = try context.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\Article.title)]))
    let refreshedSource = try #require(try context.fetch(FetchDescriptor<Source>()).first)

    #expect(summary.refreshedSourceCount == 1)
    #expect(summary.insertedCount == 2)
    #expect(summary.skippedCount == 0)
    #expect(summary.failedCount == 0)
    #expect(articles.map(\.title) == ["First RSS Post", "Second RSS Post"])
    #expect(refreshedSource.lastSuccessfulFetchAt != nil)
    #expect(refreshedSource.lastErrorMessage == nil)
}

@MainActor
@Test func feedRefreshActorSkipsDuplicatesOnSecondRefresh() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    let feedURL = URL(string: "https://example.com/actor-duplicate-rss.xml")!
    context.insert(Source(title: "Example RSS", url: feedURL, kind: .rss))
    try context.save()

    MockFeedURLProtocol.register(.success(try fixtureData("rss", extension: "xml")), for: feedURL)
    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    _ = await actor.refreshAll()
    let secondSummary = await actor.refreshAll()
    let refreshedSource = try #require(try context.fetch(FetchDescriptor<Source>()).first)

    #expect(secondSummary.insertedCount == 0)
    #expect(secondSummary.skippedCount == 2)
    #expect(secondSummary.failedCount == 0)
    #expect(refreshedSource.lastErrorMessage == nil)
    #expect(try context.fetch(FetchDescriptor<Article>()).count == 2)
}

@MainActor
@Test func feedRefreshActorUpdatesSourceErrorMetadataAfterFailure() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    let feedURL = URL(string: "https://example.com/actor-broken-rss.xml")!
    context.insert(Source(title: "Broken RSS", url: feedURL, kind: .rss))
    try context.save()

    MockFeedURLProtocol.register(.failure(statusCode: 500), for: feedURL)
    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    let summary = await actor.refreshFast()
    let refreshedSource = try #require(try context.fetch(FetchDescriptor<Source>()).first)

    #expect(summary.refreshedSourceCount == 0)
    #expect(summary.failedCount == 1)
    #expect(refreshedSource.lastFetchedAt != nil)
    #expect(refreshedSource.lastSuccessfulFetchAt == nil)
    #expect(refreshedSource.lastErrorMessage?.contains("HTTP 500") == true)
    #expect(refreshedSource.consecutiveFailureCount == 1)
}

@MainActor
@Test func feedRefreshActorRetriesDegradedSourcesInRecoveryLane() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    let feedURL = URL(string: "https://example.com/degraded-rss.xml")!
    context.insert(Source(
        title: "Degraded RSS",
        url: feedURL,
        kind: .rss,
        lastErrorMessage: "Previous timeout",
        consecutiveFailureCount: 1
    ))
    try context.save()

    MockFeedURLProtocol.register(.success(try fixtureData("rss", extension: "xml")), for: feedURL)
    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    let summary = await actor.refreshAll()
    let refreshedSource = try #require(try context.fetch(FetchDescriptor<Source>()).first)

    #expect(summary.fastInsertedCount == 0)
    #expect(summary.recoveryInsertedCount == 2)
    #expect(summary.recoveredSourceCount == 1)
    #expect(refreshedSource.lastErrorMessage == nil)
    #expect(refreshedSource.consecutiveFailureCount == 0)
}

@MainActor
@Test func feedRefreshActorRetriesFastLaneFailuresInRecoveryLane() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    let feedURL = URL(string: "https://example.com/fast-fails-then-recovers.xml")!
    context.insert(Source(title: "Flaky RSS", url: feedURL, kind: .rss))
    try context.save()

    MockFeedURLProtocol.registerSequence([
        .failure(statusCode: 504),
        .success(try fixtureData("rss", extension: "xml"))
    ], for: feedURL)
    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    let summary = await actor.refreshAll()
    let refreshedSource = try #require(try context.fetch(FetchDescriptor<Source>()).first)
    let requestedURLs = MockFeedURLProtocol.requestedURLs(matching: [feedURL])

    #expect(requestedURLs == [feedURL, feedURL])
    #expect(summary.fastInsertedCount == 0)
    #expect(summary.recoveryInsertedCount == 2)
    #expect(summary.failedCount == 1)
    #expect(summary.recoveredSourceCount == 1)
    #expect(refreshedSource.lastErrorMessage == nil)
    #expect(refreshedSource.consecutiveFailureCount == 0)
}

@MainActor
@Test func feedRefreshActorRetriesDeadSourcesInRecoveryLane() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    let feedURL = URL(string: "https://example.com/dead-rss.xml")!
    let source = Source(
        title: "Dead RSS",
        url: feedURL,
        kind: .rss,
        lastErrorMessage: "Repeated timeout",
        consecutiveFailureCount: 3
    )
    context.insert(source)
    try context.save()

    MockFeedURLProtocol.register(.success(try fixtureData("rss", extension: "xml")), for: feedURL)
    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    let summary = await actor.refreshAll()
    let refreshedSource = try #require(try context.fetch(FetchDescriptor<Source>()).first)

    #expect(summary.deadSourceCount == 1)
    #expect(summary.fastInsertedCount == 0)
    #expect(summary.recoveryInsertedCount == 2)
    #expect(summary.recoveredSourceCount == 1)
    #expect(refreshedSource.lastErrorMessage == nil)
    #expect(refreshedSource.consecutiveFailureCount == 0)
}

@MainActor
@Test func feedRefreshActorExplicitRefreshCanRecoverDeadSource() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    let feedURL = URL(string: "https://example.com/dead-explicit-rss.xml")!
    let source = Source(
        title: "Dead RSS",
        url: feedURL,
        kind: .rss,
        lastErrorMessage: "Repeated timeout",
        consecutiveFailureCount: 3
    )
    context.insert(source)
    try context.save()

    MockFeedURLProtocol.register(.success(try fixtureData("rss", extension: "xml")), for: feedURL)
    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    let explicitSummary = await actor.refresh(sourceID: source.id)
    let refreshedSource = try #require(try context.fetch(FetchDescriptor<Source>()).first)

    #expect(explicitSummary.insertedCount == 2)
    #expect(refreshedSource.lastErrorMessage == nil)
    #expect(refreshedSource.consecutiveFailureCount == 0)
}

@MainActor
@Test func feedRefreshActorRefreshesHackerNewsSourceThroughFirebase() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    let source = Source(
        title: "Hacker News Show, 10+ points",
        url: URL(string: "https://hnrss.org/show?points=10&count=20")!,
        kind: .hackerNews,
        category: "Hacker News"
    )
    context.insert(source)
    try context.save()

    MockFeedURLProtocol.register(.success(showNewHTML(ids: [101, 102, 103], nextPage: nil).data(using: .utf8)!), for: URL(string: "https://news.ycombinator.com/shownew")!)
    MockFeedURLProtocol.register(.success(hackerNewsItemJSON(id: 101, title: "Show HN: First", points: 12, comments: 2)), for: URL(string: "https://hacker-news.firebaseio.com/v0/item/101.json")!)
    MockFeedURLProtocol.register(.success(hackerNewsItemJSON(id: 102, title: "Show HN: Filtered", points: 2, comments: 4)), for: URL(string: "https://hacker-news.firebaseio.com/v0/item/102.json")!)
    MockFeedURLProtocol.register(.success(hackerNewsItemJSON(id: 103, title: "Show HN: Third", points: 20, comments: 5)), for: URL(string: "https://hacker-news.firebaseio.com/v0/item/103.json")!)
    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    let summary = await actor.refreshAll()
    let articles = try context.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\Article.title)]))
    let refreshedSource = try #require(try context.fetch(FetchDescriptor<Source>()).first)

    #expect(summary.refreshedSourceCount == 1)
    #expect(summary.insertedCount == 2)
    #expect(summary.skippedCount == 0)
    #expect(summary.failedCount == 0)
    #expect(articles.map(\.title) == ["Show HN: First", "Show HN: Third"])
    #expect(articles.map(\.score) == [14, 25])
    #expect(refreshedSource.url.absoluteString == "https://news.ycombinator.com/shownew?points=10&count=20")
    #expect(refreshedSource.lastSuccessfulFetchAt != nil)
}

@MainActor
@Test func feedRefreshActorRefreshesHackerNewsPhaseBeforeOtherSources() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    let blogURL = URL(string: "https://example.com/priority-blog-rss.xml")!
    let hackerNewsListURL = URL(string: "https://news.ycombinator.com/shownew")!
    context.insert(Source(title: "A Blog", url: blogURL, kind: .rss))
    context.insert(Source(
        title: "Z Hacker News Show",
        url: URL(string: "https://news.ycombinator.com/shownew?count=1")!,
        kind: .hackerNews
    ))
    try context.save()

    MockFeedURLProtocol.register(.success(try fixtureData("rss", extension: "xml")), for: blogURL)
    MockFeedURLProtocol.register(.success(showNewHTML(ids: [9_101], nextPage: nil).data(using: .utf8)!), for: hackerNewsListURL)
    MockFeedURLProtocol.register(.success(hackerNewsItemJSON(id: 9_101, title: "Show HN: Priority", points: 20, comments: 5)), for: URL(string: "https://hacker-news.firebaseio.com/v0/item/9101.json")!)
    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    _ = await actor.refreshAll()
    let requestOrder = MockFeedURLProtocol.requestedURLs(matching: [blogURL, hackerNewsListURL])

    #expect(requestOrder.first == hackerNewsListURL)
}

@MainActor
@Test func feedRefreshActorSkipsDuplicateHackerNewsArticlesOnSecondRefresh() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    context.insert(Source(
        title: "Hacker News Best",
        url: URL(string: "https://hacker-news.firebaseio.com/v0/beststories.json?count=2")!,
        kind: .hackerNews
    ))
    try context.save()

    MockFeedURLProtocol.register(.success("[101,103]".data(using: .utf8)!), for: URL(string: "https://hacker-news.firebaseio.com/v0/beststories.json")!)
    MockFeedURLProtocol.register(.success(hackerNewsItemJSON(id: 101, title: "Show HN: First", points: 12, comments: 2)), for: URL(string: "https://hacker-news.firebaseio.com/v0/item/101.json")!)
    MockFeedURLProtocol.register(.success(hackerNewsItemJSON(id: 103, title: "Show HN: Third", points: 20, comments: 5)), for: URL(string: "https://hacker-news.firebaseio.com/v0/item/103.json")!)
    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    _ = await actor.refreshAll()
    let secondSummary = await actor.refreshAll()

    #expect(secondSummary.insertedCount == 0)
    #expect(secondSummary.skippedCount == 2)
    #expect(secondSummary.failedCount == 0)
}

@MainActor
@Test func feedRefreshActorRefreshesOtherSourcesWithBoundedConcurrency() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    let sourceURLs = (0..<60).map { URL(string: "https://bounded-\($0).example.com/rss.xml")! }
    for (index, url) in sourceURLs.enumerated() {
        context.insert(Source(title: "Bounded \(index)", url: url, kind: .rss))
        MockFeedURLProtocol.register(.success(try fixtureData("rss", extension: "xml")), for: url, delay: 0.08)
    }
    try context.save()
    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    _ = await actor.refreshAll()
    let maxOverlap = MockFeedURLProtocol.maxConcurrentRequests(for: sourceURLs)

    #expect(maxOverlap > 5)
    #expect(maxOverlap <= 50)
}

@MainActor
@Test func feedRefreshActorRunsRetentionAfterRefresh() async throws {
    let container = try refreshActorTestContainer()
    let context = container.mainContext
    let now = Date()
    let oldUnstarred = Article(
        id: "old-unstarred",
        sourceID: UUID(),
        sourceTitle: "Example",
        title: "Old Unstarred",
        url: URL(string: "https://example.com/old-unstarred")!,
        fetchedAt: now.addingTimeInterval(-8 * 86_400)
    )
    let oldStarred = Article(
        id: "old-starred",
        sourceID: UUID(),
        sourceTitle: "Example",
        title: "Old Starred",
        url: URL(string: "https://example.com/old-starred")!,
        fetchedAt: now.addingTimeInterval(-8 * 86_400),
        isStarred: true
    )
    context.insert(AppSettings(retentionDays: 7))
    context.insert(oldUnstarred)
    context.insert(oldStarred)
    try context.save()

    let actor = FeedRefreshActor(
        modelContainer: container,
        httpClient: FeedHTTPClient(session: mockFeedSession())
    )

    let summary = await actor.refreshAll()
    let remainingIDs = try context.fetch(FetchDescriptor<Article>()).map(\.id).sorted()
    let settings = try #require(try context.fetch(FetchDescriptor<AppSettings>()).first)

    #expect(summary.retentionDeletedCount == 1)
    #expect(settings.lastRetentionDeletedCount == 1)
    #expect(settings.lastRetentionCleanupAt != nil)
    #expect(remainingIDs == ["old-starred"])
}

@MainActor
private func refreshActorTestContainer() throws -> ModelContainer {
    return try ModelContainer(
        for: Source.self, Article.self, AppSettings.self, FilterRule.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func mockFeedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockFeedURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func fixtureData(_ name: String, extension ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func hackerNewsItemJSON(id: Int, title: String, points: Int, comments: Int) -> Data {
    """
    {
      "id": \(id),
      "type": "story",
      "by": "tester",
      "time": 1781621018,
      "title": "\(title)",
      "url": "https://example.com/\(id)",
      "text": "Author text",
      "score": \(points),
      "descendants": \(comments)
    }
    """.data(using: .utf8)!
}

private final class MockFeedURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response {
        case success(Data, statusCode: Int = 200)
        case failure(statusCode: Int)
    }

    nonisolated(unsafe) private static var responses: [URL: Response] = [:]
    nonisolated(unsafe) private static var responseSequences: [URL: [Response]] = [:]
    nonisolated(unsafe) private static var delays: [URL: TimeInterval] = [:]
    nonisolated(unsafe) private static var events: [(url: URL, isStart: Bool, date: Date)] = []
    private static let lock = NSLock()

    static func register(_ response: Response, for url: URL, delay: TimeInterval = 0) {
        lock.lock()
        responses[url] = response
        delays[url] = delay
        lock.unlock()
    }

    static func registerSequence(_ sequence: [Response], for url: URL, delay: TimeInterval = 0) {
        lock.lock()
        responseSequences[url] = sequence
        delays[url] = delay
        lock.unlock()
    }

    static func requestedURLs(matching urls: [URL]) -> [URL] {
        let urlSet = Set(urls)
        lock.lock()
        let requested = events.filter { $0.isStart && urlSet.contains($0.url) }.map(\.url)
        lock.unlock()
        return requested
    }

    static func maxConcurrentRequests(for urls: [URL]) -> Int {
        let urlSet = Set(urls)
        lock.lock()
        let matchingEvents = events.filter { urlSet.contains($0.url) }
        lock.unlock()

        var active = 0
        var maxActive = 0
        for event in matchingEvents.sorted(by: { $0.date < $1.date }) {
            if event.isStart {
                active += 1
                maxActive = max(maxActive, active)
            } else {
                active = max(0, active - 1)
            }
        }
        return maxActive
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = Self.response(for: url) else {
            send(statusCode: 404, data: Data())
            return
        }
        Self.record(url: url, isStart: true)
        guard let delay = Self.delay(for: url), delay > 0 else {
            send(response)
            Self.record(url: url, isStart: false)
            return
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.send(response)
            Self.record(url: url, isStart: false)
        }
    }

    override func stopLoading() {}

    private static func response(for url: URL) -> Response? {
        lock.lock()
        defer { lock.unlock() }
        if var sequence = responseSequences[url], !sequence.isEmpty {
            let response = sequence.removeFirst()
            responseSequences[url] = sequence
            return response
        }
        return responses[url]
    }

    private static func delay(for url: URL) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return delays[url]
    }

    private static func record(url: URL, isStart: Bool) {
        lock.lock()
        events.append((url: url, isStart: isStart, date: Date()))
        lock.unlock()
    }

    private func send(statusCode: Int, data: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func send(_ response: Response) {
        switch response {
        case .success(let data, let statusCode):
            send(statusCode: statusCode, data: data)
        case .failure(let statusCode):
            send(statusCode: statusCode, data: Data())
        }
    }
}
