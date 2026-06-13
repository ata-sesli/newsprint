import Foundation
import Testing
@testable import newsprintCore

@Test func importsFlatOPMLSources() throws {
    let data = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <body>
        <outline text="Example" title="Example" type="rss" xmlUrl="https://example.com/feed.xml" htmlUrl="https://example.com"/>
      </body>
    </opml>
    """.utf8)

    let preview = try OPMLImporter().preview(data: data)

    #expect(preview.sources.count == 1)
    #expect(preview.sources[0].title == "Example")
    #expect(preview.sources[0].feedURL.absoluteString == "https://example.com/feed.xml")
    #expect(preview.sources[0].siteURL?.absoluteString == "https://example.com")
    #expect(preview.sources[0].category == nil)
}

@Test func importsFolderedOPMLSourcesAsCategories() throws {
    let data = Data("""
    <opml version="2.0">
      <body>
        <outline text="AI">
          <outline text="OpenAI" type="rss" xmlUrl="https://openai.com/news/rss.xml"/>
        </outline>
      </body>
    </opml>
    """.utf8)

    let preview = try OPMLImporter().preview(data: data)

    #expect(preview.sources.count == 1)
    #expect(preview.sources[0].category == "AI")
}

@Test func importsSiblingFeedsInFolderWithSameCategory() throws {
    let data = Data("""
    <opml version="2.0">
      <body>
        <outline text="AI">
          <outline text="OpenAI" type="rss" xmlUrl="https://openai.com/news/rss.xml"/>
          <outline text="Anthropic" type="rss" xmlUrl="https://www.anthropic.com/news/rss.xml"/>
        </outline>
      </body>
    </opml>
    """.utf8)

    let preview = try OPMLImporter().preview(data: data)

    #expect(preview.sources.map(\.category) == ["AI", "AI"])
}

@Test func importsNestedFolderFeedsWithNearestCategory() throws {
    let data = Data("""
    <opml version="2.0">
      <body>
        <outline text="Technology">
          <outline text="Systems">
            <outline text="Oxide" type="rss" xmlUrl="https://oxide.computer/blog/rss.xml"/>
          </outline>
        </outline>
      </body>
    </opml>
    """.utf8)

    let preview = try OPMLImporter().preview(data: data)

    #expect(preview.sources.count == 1)
    #expect(preview.sources[0].category == "Systems")
}

@Test func exportsSourcesGroupedByCategory() throws {
    let sources = [
        Source(title: "OpenAI", url: URL(string: "https://openai.com/news/rss.xml")!, siteURL: URL(string: "https://openai.com"), category: "AI"),
        Source(title: "Rust Blog", url: URL(string: "https://blog.rust-lang.org/feed.xml")!, category: "Programming")
    ]

    let data = try OPMLExporter().export(sources: sources, title: "Newsprint Sources")
    let xml = try #require(String(data: data, encoding: .utf8))

    #expect(xml.contains("<title>Newsprint Sources</title>"))
    #expect(xml.contains("<outline text=\"AI\">"))
    #expect(xml.contains("xmlUrl=\"https://openai.com/news/rss.xml\""))
    #expect(xml.contains("htmlUrl=\"https://openai.com\""))
    #expect(xml.contains("<outline text=\"Programming\">"))
}

@Test func exportsStarredArticlesAsMarkdown() {
    let starred = Article(
        id: "starred",
        sourceID: UUID(),
        sourceTitle: "Example",
        title: "Worth Saving",
        url: URL(string: "https://example.com/save")!,
        isStarred: true
    )
    let hidden = Article(
        id: "hidden",
        sourceID: UUID(),
        sourceTitle: "Example",
        title: "Not Starred",
        url: URL(string: "https://example.com/skip")!
    )

    let markdown = StarredArticleExporter().markdown(for: [hidden, starred])

    #expect(markdown.contains("# Starred Articles"))
    #expect(markdown.contains("- [Worth Saving](https://example.com/save)"))
    #expect(!markdown.contains("Not Starred"))
}
