import Foundation
import Testing
@testable import newsprintCore

@Test func hackerNewsAPIPreservesOrderAndAppliesLocalFilters() async throws {
    let source = SourceSnapshot(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000feed")!,
        title: "Hacker News Show",
        url: try #require(URL(string: "https://hacker-news.firebaseio.com/v0/showstories.json?points=10&comments=2&count=2")),
        kind: .hackerNews
    )
    MockHackerNewsURLProtocol.register("[101,102,103]".data(using: .utf8)!, for: "https://hacker-news.firebaseio.com/v0/showstories.json")
    MockHackerNewsURLProtocol.register(itemJSON(id: 101, title: "First", points: 12, comments: 2), for: "https://hacker-news.firebaseio.com/v0/item/101.json")
    MockHackerNewsURLProtocol.register(itemJSON(id: 102, title: "Filtered", points: 2, comments: 10), for: "https://hacker-news.firebaseio.com/v0/item/102.json")
    MockHackerNewsURLProtocol.register(itemJSON(id: 103, title: "Third", points: 20, comments: 5), for: "https://hacker-news.firebaseio.com/v0/item/103.json")
    let client = HackerNewsAPIClient(httpClient: FeedHTTPClient(session: mockHackerNewsSession()))

    let drafts = try await client.fetchDrafts(for: source)

    #expect(drafts.map(\.title) == ["First", "Third"])
}

@Test func hackerNewsAPIFetchesItemsConcurrentlyWhilePreservingOrder() async throws {
    let source = SourceSnapshot(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000feed")!,
        title: "Hacker News Best",
        url: try #require(URL(string: "https://hacker-news.firebaseio.com/v0/beststories.json?count=3")),
        kind: .hackerNews
    )
    let ids = [9_001, 9_002, 9_003]
    MockHackerNewsURLProtocol.register("[\(ids.map(String.init).joined(separator: ","))]".data(using: .utf8)!, for: "https://hacker-news.firebaseio.com/v0/beststories.json")
    MockHackerNewsURLProtocol.register(itemJSON(id: ids[0], title: "First", points: 12, comments: 2), for: "https://hacker-news.firebaseio.com/v0/item/\(ids[0]).json", delay: 0.08)
    MockHackerNewsURLProtocol.register(itemJSON(id: ids[1], title: "Second", points: 13, comments: 3), for: "https://hacker-news.firebaseio.com/v0/item/\(ids[1]).json", delay: 0.08)
    MockHackerNewsURLProtocol.register(itemJSON(id: ids[2], title: "Third", points: 14, comments: 4), for: "https://hacker-news.firebaseio.com/v0/item/\(ids[2]).json", delay: 0.08)
    let client = HackerNewsAPIClient(httpClient: FeedHTTPClient(session: mockHackerNewsSession()))

    let drafts = try await client.fetchDrafts(for: source)
    let maxOverlap = MockHackerNewsURLProtocol.maxConcurrentRequests(forItemIDs: ids)

    #expect(drafts.map(\.title) == ["First", "Second", "Third"])
    #expect(maxOverlap > 1)
}

@Test func hackerNewsAPIStopsFetchingAfterAcceptedCount() async throws {
    let source = SourceSnapshot(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000feed")!,
        title: "Hacker News Jobs",
        url: try #require(URL(string: "https://hacker-news.firebaseio.com/v0/jobstories.json?count=20")),
        kind: .hackerNews
    )
    let ids = Array(9_020...9_040)
    MockHackerNewsURLProtocol.register("[\(ids.map(String.init).joined(separator: ","))]".data(using: .utf8)!, for: "https://hacker-news.firebaseio.com/v0/jobstories.json")
    for id in ids {
        MockHackerNewsURLProtocol.register(itemJSON(id: id, title: "Item \(id)", points: 10, comments: 1), for: "https://hacker-news.firebaseio.com/v0/item/\(id).json")
    }
    let client = HackerNewsAPIClient(httpClient: FeedHTTPClient(session: mockHackerNewsSession()))

    let drafts = try await client.fetchDrafts(for: source)
    let requestedIDs = MockHackerNewsURLProtocol.requestedItemIDs(ids)

    #expect(drafts.map(\.title) == ids.prefix(20).map { "Item \($0)" })
    #expect(Set(requestedIDs) == Set(ids.prefix(20)))
    #expect(!requestedIDs.contains(9_040))
}

@Test func hackerNewsAPIUsesFourSecondItemTimeoutDuringRecoveryRefresh() async throws {
    let source = SourceSnapshot(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000feed")!,
        title: "Hacker News Newest",
        url: try #require(URL(string: "https://hacker-news.firebaseio.com/v0/newstories.json?count=1")),
        kind: .hackerNews
    )
    let listURL = try #require(URL(string: "https://hacker-news.firebaseio.com/v0/newstories.json"))
    let itemURL = try #require(URL(string: "https://hacker-news.firebaseio.com/v0/item/9901.json"))
    MockHackerNewsURLProtocol.register("[9901]".data(using: .utf8)!, for: listURL.absoluteString)
    MockHackerNewsURLProtocol.register(itemJSON(id: 9_901, title: "Timed", points: 12, comments: 2), for: itemURL.absoluteString)
    let client = HackerNewsAPIClient(httpClient: FeedHTTPClient(session: mockHackerNewsSession()))

    _ = try await client.fetchDrafts(for: source, timeout: FeedHTTPClient.recoverySourceRefreshTimeout)

    #expect(MockHackerNewsURLProtocol.timeout(for: itemURL) == 4)
}

@Test func hackerNewsArticleMapperUsesSubmittedURLAndMetadata() throws {
    let source = SourceSnapshot(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000feed")!,
        title: "Hacker News Show",
        url: try #require(URL(string: "https://hacker-news.firebaseio.com/v0/showstories.json")),
        kind: .hackerNews
    )
    let item = HackerNewsItem(
        id: 101,
        type: "story",
        by: "alice",
        time: 1_781_621_018,
        title: "Show HN: Example",
        url: URL(string: "https://example.com"),
        text: "I built this.<p>It works.",
        score: 42,
        descendants: 3,
        deleted: nil,
        dead: nil
    )

    let draft = try #require(HackerNewsArticleMapper.draft(from: item, source: source))
    let metadata = try #require(HackerNewsMetadata(text: draft.contentText))

    #expect(draft.url.absoluteString == "https://example.com")
    #expect(draft.author == "alice")
    #expect(draft.externalID == "hn:101")
    #expect(metadata.articleURL?.absoluteString == "https://example.com")
    #expect(metadata.threadURL?.absoluteString == "https://news.ycombinator.com/item?id=101")
    #expect(metadata.points == 42)
    #expect(metadata.commentCount == 3)
    #expect(metadata.authorComment == "I built this. It works.")
}

@Test func hackerNewsArticleMapperUsesThreadURLForSelfPosts() throws {
    let source = SourceSnapshot(
        id: UUID(),
        title: "Hacker News Show",
        url: try #require(URL(string: "https://hacker-news.firebaseio.com/v0/showstories.json")),
        kind: .hackerNews
    )
    let item = HackerNewsItem(
        id: 202,
        type: "story",
        by: "bob",
        time: 1_781_621_018,
        title: "Show HN: Self Post",
        url: nil,
        text: "Ask me anything.",
        score: 5,
        descendants: 1,
        deleted: nil,
        dead: nil
    )

    let draft = try #require(HackerNewsArticleMapper.draft(from: item, source: source))

    #expect(draft.url.absoluteString == "https://news.ycombinator.com/item?id=202")
}

private func mockHackerNewsSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockHackerNewsURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func itemJSON(id: Int, title: String, points: Int, comments: Int) -> Data {
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

private final class MockHackerNewsURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var responses: [URL: Data] = [:]
    nonisolated(unsafe) private static var delays: [URL: TimeInterval] = [:]
    nonisolated(unsafe) private static var events: [(url: URL, isStart: Bool, date: Date)] = []
    nonisolated(unsafe) private static var timeouts: [URL: TimeInterval] = [:]
    private static let lock = NSLock()

    static func register(_ data: Data, for urlString: String, delay: TimeInterval = 0) {
        lock.lock()
        let url = URL(string: urlString)!
        responses[url] = data
        delays[url] = delay
        lock.unlock()
    }

    static func timeout(for url: URL) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return timeouts[url]
    }

    static func requestedItemIDs(_ ids: [Int]) -> [Int] {
        let idSet = Set(ids)
        lock.lock()
        let urls = events.filter(\.isStart).map(\.url)
        lock.unlock()
        return urls.compactMap { url in
            guard url.path.hasPrefix("/v0/item/"),
                  let id = Int(url.deletingPathExtension().lastPathComponent),
                  idSet.contains(id) else {
                return nil
            }
            return id
        }
    }

    static func maxConcurrentRequests(forItemIDs ids: [Int]) -> Int {
        let idSet = Set(ids)
        lock.lock()
        let matchingEvents = events.filter { event in
            guard event.url.path.hasPrefix("/v0/item/"),
                  let id = Int(event.url.deletingPathExtension().lastPathComponent) else {
                return false
            }
            return idSet.contains(id)
        }
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
              let data = Self.response(for: url) else {
            send(statusCode: 404, data: Data())
            return
        }
        Self.record(url: url, isStart: true)
        Self.recordTimeout(request.timeoutInterval, for: url)
        guard let delay = Self.delay(for: url), delay > 0 else {
            send(statusCode: 200, data: data)
            Self.record(url: url, isStart: false)
            return
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.send(statusCode: 200, data: data)
            Self.record(url: url, isStart: false)
        }
    }

    override func stopLoading() {}

    private static func response(for url: URL) -> Data? {
        lock.lock()
        defer { lock.unlock() }
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

    private static func recordTimeout(_ timeout: TimeInterval, for url: URL) {
        lock.lock()
        timeouts[url] = timeout
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
}
