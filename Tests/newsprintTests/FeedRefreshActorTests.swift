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

    let summary = await actor.refreshAll()
    let refreshedSource = try #require(try context.fetch(FetchDescriptor<Source>()).first)

    #expect(summary.refreshedSourceCount == 0)
    #expect(summary.failedCount == 1)
    #expect(refreshedSource.lastFetchedAt != nil)
    #expect(refreshedSource.lastSuccessfulFetchAt == nil)
    #expect(refreshedSource.lastErrorMessage?.contains("HTTP 500") == true)
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
    try ModelContainer(
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

private final class MockFeedURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response {
        case success(Data, statusCode: Int = 200)
        case failure(statusCode: Int)
    }

    nonisolated(unsafe) private static var responses: [URL: Response] = [:]
    private static let lock = NSLock()

    static func register(_ response: Response, for url: URL) {
        lock.lock()
        responses[url] = response
        lock.unlock()
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

        switch response {
        case .success(let data, let statusCode):
            send(statusCode: statusCode, data: data)
        case .failure(let statusCode):
            send(statusCode: statusCode, data: Data())
        }
    }

    override func stopLoading() {}

    private static func response(for url: URL) -> Response? {
        lock.lock()
        defer { lock.unlock() }
        return responses[url]
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
}
