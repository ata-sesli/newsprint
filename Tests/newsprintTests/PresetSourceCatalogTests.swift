import Foundation
import SwiftData
import Testing
@testable import newsprintCore

@Test func presetCatalogMatchesTop50CoreFeedPack() throws {
    let presets = PresetSourceCatalog.all

    #expect(presets.count == 50)
    #expect(presets.map(\.title) == presets.map(\.title).sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    })
    #expect(presets.first?.title == "Ahead of AI")
    #expect(presets.first?.category == "AI Research & Digests")
    #expect(presets.first?.url.absoluteString == "https://magazine.sebastianraschka.com/feed")
    #expect(presets.last?.title == "Web Browser Engineering")
    #expect(presets.last?.category == "Low-Level & Systems Engineering")
    #expect(presets.last?.url.absoluteString == "https://browser.engineering/rss.xml")

    let titles = Set(presets.map(\.title))
    for title in [
        "Datadog Engineering",
        "Fabien Sanglard",
        "Google Research Blog",
        "Cloudflare Blog",
        "Hugging Face Blog",
        "Jane Street Tech Blog",
        "Meta Engineering",
        "Null Program",
        "PortSwigger Research",
        "Project Zero",
        "Rust Blog",
        "The Pragmatic Engineer"
    ] {
        #expect(titles.contains(title))
    }

    #expect(!titles.contains("ACM Queue"))
    #expect(!titles.contains("BAIR Blog"))
    #expect(!titles.contains("Computer, Enhance!"))
    #expect(!titles.contains("Google Project Zero"))
    #expect(!titles.contains("NCC Group Research"))
    #expect(!titles.contains("Netflix TechBlog"))
    #expect(!titles.contains("Stripe Engineering"))
    #expect(!titles.contains("OpenAI News"))
    #expect(!titles.contains("Anthropic News"))
    #expect(!titles.contains("Hacker News Front Page"))
}

@Test func youtubeChannelIDBuildsFeedURL() throws {
    let url = try #require(PresetSourceCatalog.youtubeFeedURL(from: "UC_x5XG1OV2P6uZZ5FSM9Ttw"))

    #expect(url.absoluteString == "https://www.youtube.com/feeds/videos.xml?channel_id=UC_x5XG1OV2P6uZZ5FSM9Ttw")
}

@MainActor
@Test func generatedHackerNewsFeedCanBeSavedAsSource() throws {
    let container = try ModelContainer(
        for: Source.self, Article.self, AppSettings.self, FilterRule.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let configuration = HackerNewsFeedConfiguration(kind: .show, minimumPoints: 50)
    let source = Source(
        title: HackerNewsFeedURLBuilder.title(for: configuration),
        url: HackerNewsFeedURLBuilder.url(for: configuration),
        kind: .hackerNews,
        category: "Hacker News"
    )

    let inserted = try SwiftDataSourceRepository(context: context).saveIfNew(source)
    let sources = try context.fetch(FetchDescriptor<Source>())

    #expect(inserted)
    #expect(sources.map(\.title) == ["Hacker News Show, 50+ points"])
    #expect(sources.map(\.url.absoluteString) == ["https://news.ycombinator.com/shownew?points=50"])
    #expect(sources.map(\.kind) == [.hackerNews])
}
