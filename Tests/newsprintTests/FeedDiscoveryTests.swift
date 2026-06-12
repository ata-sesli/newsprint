import Foundation
import Testing
@testable import newsprintCore

@MainActor
@Test func discoveryReturnsDirectFeedWhenURLParsesAsFeed() async throws {
    let feedURL = URL(string: "https://example.com/feed.xml")!
    let service = FeedDiscoveryService(fetcher: StubDiscoveryFetcher(responses: [
        feedURL: try fixtureData("rss", extension: "xml")
    ]))

    let result = try await service.discover(from: feedURL)

    guard case .directFeed(let feed) = result else {
        Issue.record("Expected direct feed")
        return
    }
    #expect(feed.url == feedURL)
    #expect(feed.type == .rss)
}

@MainActor
@Test func discoveryFindsAlternateFeedLinksInHTML() async throws {
    let pageURL = URL(string: "https://example.com/blog")!
    let service = FeedDiscoveryService(fetcher: StubDiscoveryFetcher(responses: [
        pageURL: try fixtureData("homepage-with-alternates", extension: "html")
    ]))

    let result = try await service.discover(from: pageURL)

    guard case .candidates(let candidates) = result else {
        Issue.record("Expected discovered candidates")
        return
    }
    #expect(candidates.map(\.url.absoluteString) == [
        "https://example.com/rss.xml",
        "https://example.com/atom.xml",
        "https://example.com/feed.json"
    ])
    #expect(candidates.map(\.type) == [.rss, .atom, .jsonFeed])
    #expect(candidates.map(\.title) == ["RSS", "Atom", "JSON"])
}

@MainActor
@Test func discoveryResolvesRelativeAlternateLinks() async throws {
    let pageURL = URL(string: "https://example.com/writing/index.html")!
    let service = FeedDiscoveryService(fetcher: StubDiscoveryFetcher(responses: [
        pageURL: try fixtureData("homepage-with-relative-feed", extension: "html")
    ]))

    let result = try await service.discover(from: pageURL)

    guard case .candidates(let candidates) = result else {
        Issue.record("Expected discovered candidates")
        return
    }
    #expect(candidates.map(\.url.absoluteString) == ["https://example.com/writing/feed.xml"])
}

@MainActor
@Test func discoveryDeduplicatesAlternateLinks() async throws {
    let pageURL = URL(string: "https://example.com/blog")!
    let service = FeedDiscoveryService(fetcher: StubDiscoveryFetcher(responses: [
        pageURL: """
        <html><head>
        <link rel="alternate" type="application/rss+xml" title="A" href="/feed.xml">
        <link rel="alternate" type="application/rss+xml" title="B" href="https://example.com/feed.xml">
        </head></html>
        """.data(using: .utf8)!
    ]))

    let result = try await service.discover(from: pageURL)

    guard case .candidates(let candidates) = result else {
        Issue.record("Expected discovered candidates")
        return
    }
    #expect(candidates.count == 1)
    #expect(candidates[0].title == "A")
}

@MainActor
@Test func discoveryProbesCommonFeedPathsWhenNoAlternatesExist() async throws {
    let pageURL = URL(string: "https://example.com/blog")!
    let probedFeedURL = URL(string: "https://example.com/feed")!
    let service = FeedDiscoveryService(fetcher: StubDiscoveryFetcher(responses: [
        pageURL: try fixtureData("homepage-without-alternates", extension: "html"),
        probedFeedURL: try fixtureData("rss", extension: "xml")
    ]))

    let result = try await service.discover(from: pageURL)

    guard case .candidates(let candidates) = result else {
        Issue.record("Expected probed candidates")
        return
    }
    #expect(candidates.map(\.url) == [probedFeedURL])
}

@MainActor
@Test func discoveryThrowsReadableErrorWhenNoFeedIsFound() async throws {
    let pageURL = URL(string: "https://example.com/blog")!
    let service = FeedDiscoveryService(fetcher: StubDiscoveryFetcher(responses: [
        pageURL: try fixtureData("homepage-without-alternates", extension: "html")
    ]))

    await #expect(throws: FeedDiscoveryError.noFeedsFound) {
        try await service.discover(from: pageURL)
    }
}

private struct StubDiscoveryFetcher: FeedDiscoveryFetching {
    let responses: [URL: Data]

    func fetch(url: URL) async throws -> Data {
        guard let data = responses[url] else {
            throw FeedDiscoveryError.noFeedsFound
        }
        return data
    }
}

private func fixtureData(_ name: String, extension ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}
