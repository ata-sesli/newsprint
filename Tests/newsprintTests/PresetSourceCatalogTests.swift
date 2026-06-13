import Foundation
import SwiftData
import Testing
@testable import newsprintCore

@Test func presetCatalogContainsRequiredMVPFeeds() throws {
    let titles = Set(PresetSourceCatalog.all.map(\.title))

    for title in [
        "Hacker News Front Page",
        "Hacker News Newest",
        "Hacker News Show",
        "Hacker News Ask",
        "OpenAI News",
        "Anthropic News",
        "Google AI Blog",
        "Google DeepMind Blog",
        "Rust Blog",
        "This Week in Rust",
        "Zig News",
        "LWN",
        "Cloudflare Blog",
        "Oxide Computer Blog",
        "Lobsters"
    ] {
        #expect(titles.contains(title))
    }
}

@Test func youtubeChannelIDBuildsFeedURL() throws {
    let url = try #require(PresetSourceCatalog.youtubeFeedURL(from: "UC_x5XG1OV2P6uZZ5FSM9Ttw"))

    #expect(url.absoluteString == "https://www.youtube.com/feeds/videos.xml?channel_id=UC_x5XG1OV2P6uZZ5FSM9Ttw")
}

@MainActor
@Test func presetCanBeSavedAsSource() throws {
    let container = try ModelContainer(
        for: Source.self, Article.self, AppSettings.self, FilterRule.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let preset = try #require(PresetSourceCatalog.all.first)
    let source = Source(
        title: preset.title,
        url: preset.url,
        kind: preset.kind,
        category: preset.category
    )

    let inserted = try SwiftDataSourceRepository(context: context).saveIfNew(source)
    let sources = try context.fetch(FetchDescriptor<Source>())

    #expect(inserted)
    #expect(sources.map(\.title) == [preset.title])
    #expect(sources.map(\.url) == [preset.url])
}
