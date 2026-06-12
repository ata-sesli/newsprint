import Foundation
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

