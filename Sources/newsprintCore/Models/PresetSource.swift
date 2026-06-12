import Foundation

public struct PresetSource: Identifiable, Hashable, Sendable {
    public var id: String { url.absoluteString }
    public let title: String
    public let url: URL
    public let category: String
    public let kind: SourceKind

    public init(title: String, url: URL, category: String, kind: SourceKind) {
        self.title = title
        self.url = url
        self.category = category
        self.kind = kind
    }
}

public enum PresetSourceCatalog {
    public static let all: [PresetSource] = [
        preset("Hacker News Front Page", "https://hnrss.org/frontpage", "Hacker News", .hackerNews),
        preset("Hacker News Newest", "https://hnrss.org/newest", "Hacker News", .hackerNews),
        preset("Hacker News Show", "https://hnrss.org/show", "Hacker News", .hackerNews),
        preset("Hacker News Ask", "https://hnrss.org/ask", "Hacker News", .hackerNews),
        preset("OpenAI News", "https://openai.com/news/rss.xml", "AI", .blog),
        preset("Anthropic News", "https://www.anthropic.com/news/rss.xml", "AI", .blog),
        preset("Google AI Blog", "https://blog.google/technology/ai/rss/", "AI", .blog),
        preset("Google DeepMind Blog", "https://deepmind.google/blog/rss.xml", "AI", .blog),
        preset("Rust Blog", "https://blog.rust-lang.org/feed.xml", "Programming", .blog),
        preset("This Week in Rust", "https://this-week-in-rust.org/rss.xml", "Programming", .blog),
        preset("Zig News", "https://zig.news/feed", "Programming", .blog),
        preset("LWN", "https://lwn.net/headlines/rss", "Technology", .blog),
        preset("Cloudflare Blog", "https://blog.cloudflare.com/rss/", "Technology", .blog),
        preset("Oxide Computer Blog", "https://oxide.computer/blog/rss.xml", "Technology", .blog),
        preset("Lobsters", "https://lobste.rs/rss", "Technology", .blog)
    ]

    public static func youtubeFeedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           url.host()?.localizedCaseInsensitiveContains("youtube.com") == true,
           url.path.contains("/feeds/videos.xml") {
            return url
        }

        var components = URLComponents(string: "https://www.youtube.com/feeds/videos.xml")
        components?.queryItems = [URLQueryItem(name: "channel_id", value: trimmed)]
        return components?.url
    }

    private static func preset(_ title: String, _ urlString: String, _ category: String, _ kind: SourceKind) -> PresetSource {
        PresetSource(title: title, url: URL(string: urlString)!, category: category, kind: kind)
    }
}

