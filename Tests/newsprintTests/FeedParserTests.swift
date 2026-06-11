import Testing
import Foundation
@testable import newsprintCore

@Test func parserNormalizesRSSFixture() throws {
    let data = try fixtureData("rss", extension: "xml")
    let source = Source.makeForTests(title: "Example RSS", url: "https://example.com/feed.xml", kind: .rss)

    let drafts = try FeedParser().parse(data: data, source: source)

    #expect(drafts.count == 2)
    #expect(drafts[0].title == "First RSS Post")
    #expect(drafts[0].url.absoluteString == "https://example.com/posts/first?utm_source=test")
    #expect(drafts[0].externalID == "rss-guid-1")
    #expect(drafts[0].contentText == "First RSS body")
}

@Test func parserNormalizesAtomFixture() throws {
    let data = try fixtureData("atom", extension: "xml")
    let source = Source.makeForTests(title: "Example Atom", url: "https://example.com/atom.xml", kind: .atom)

    let drafts = try FeedParser().parse(data: data, source: source)

    #expect(drafts.count == 1)
    #expect(drafts[0].title == "First Atom Post")
    #expect(drafts[0].url.absoluteString == "https://example.com/atom/first")
    #expect(drafts[0].author == "Atom Author")
}

@Test func parserNormalizesJSONFeedFixture() throws {
    let data = try fixtureData("jsonfeed", extension: "json")
    let source = Source.makeForTests(title: "Example JSON", url: "https://example.com/feed.json", kind: .jsonFeed)

    let drafts = try FeedParser().parse(data: data, source: source)

    #expect(drafts.count == 1)
    #expect(drafts[0].title == "First JSON Feed Post")
    #expect(drafts[0].url.absoluteString == "https://example.com/json/first")
    #expect(drafts[0].externalID == "json-1")
}

private func fixtureData(_ name: String, extension ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

