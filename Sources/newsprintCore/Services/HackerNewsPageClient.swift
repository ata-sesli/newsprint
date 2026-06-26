import Foundation

public struct HackerNewsPageItem: Sendable, Equatable {
    public let id: Int
    public let rank: Int
    public let title: String
    public let url: URL?
    public let author: String?
    public let points: Int?
    public let commentCount: Int
    public let postedAt: Date?
    public let commentsURL: URL

    public init(
        id: Int,
        rank: Int,
        title: String,
        url: URL?,
        author: String?,
        points: Int?,
        commentCount: Int,
        postedAt: Date?,
        commentsURL: URL
    ) {
        self.id = id
        self.rank = rank
        self.title = title
        self.url = url
        self.author = author
        self.points = points
        self.commentCount = commentCount
        self.postedAt = postedAt
        self.commentsURL = commentsURL
    }
}

public struct HackerNewsPage: Sendable, Equatable {
    public let items: [HackerNewsPageItem]
    public let nextPage: Int?

    public init(items: [HackerNewsPageItem], nextPage: Int?) {
        self.items = items
        self.nextPage = nextPage
    }
}

public enum HackerNewsPageParseError: Error, LocalizedError {
    case invalidHTML
    case noItems

    public var errorDescription: String? {
        switch self {
        case .invalidHTML:
            "Could not parse Hacker News page HTML"
        case .noItems:
            "Hacker News page contained no items"
        }
    }
}

public struct HackerNewsPageClient: Sendable {
    private static let baseURL = URL(string: "https://news.ycombinator.com")!
    private let httpClient: FeedHTTPClient

    public init(httpClient: FeedHTTPClient = FeedHTTPClient()) {
        self.httpClient = httpClient
    }

    public func fetchShowNewPage(page: Int = 1, timeout: TimeInterval = FeedHTTPClient.sourceRefreshTimeout) async throws -> HackerNewsPage {
        let response = try await httpClient.fetch(url: showNewURL(page: page), timeout: timeout)
        guard let html = String(data: response.data, encoding: .utf8) else {
            throw HackerNewsPageParseError.invalidHTML
        }
        return try Self.parseShowNewPage(html: html)
    }

    public static func parseShowNewPage(html: String) throws -> HackerNewsPage {
        let itemPattern = #"(?s)<tr class=['"]athing submission['"] id=['"](\d+)['"].*?<span class=['"]rank['"]>(\d+)\.</span>.*?<span class=['"]titleline['"]><a href=['"]([^'"]+)['"][^>]*>(.*?)</a>.*?</tr>\s*<tr><td colspan=['"]2['"]></td><td class=['"]subtext['"]>(.*?)</td></tr>"#
        let itemMatches = matches(for: itemPattern, in: html)
        let items = itemMatches.compactMap { match -> HackerNewsPageItem? in
            guard match.count >= 6,
                  let id = Int(match[1]),
                  let rank = Int(match[2]) else {
                return nil
            }

            let threadURL = Self.baseURL.appendingPathComponent("item").newsprintAppending(queryItems: [
                URLQueryItem(name: "id", value: "\(id)")
            ])
            let url = Self.resolvedURL(from: match[3], fallbackThreadURL: threadURL)
            let subtext = match[5]
            return HackerNewsPageItem(
                id: id,
                rank: rank,
                title: HTMLTextExtractor.text(fromHTML: match[4]),
                url: url,
                author: Self.firstCapture(#"class=['"]hnuser['"]>([^<]+)</a>"#, in: subtext).map { HTMLTextExtractor.text(fromHTML: $0) },
                points: Self.firstInt(#"class=['"]score['"][^>]*>(\d+)\s+points?</span>"#, in: subtext),
                commentCount: Self.commentCount(from: subtext),
                postedAt: Self.postedAt(from: subtext),
                commentsURL: threadURL
            )
        }

        guard !itemMatches.isEmpty else {
            throw HackerNewsPageParseError.noItems
        }
        guard !items.isEmpty else {
            throw HackerNewsPageParseError.invalidHTML
        }

        return HackerNewsPage(
            items: items,
            nextPage: Self.firstInt(#"href=['"]shownew\?p=(\d+)['"][^>]*class=['"]morelink['"]"#, in: html)
        )
    }

    private func showNewURL(page: Int) -> URL {
        if page <= 1 {
            return Self.baseURL.appendingPathComponent("shownew")
        }
        return Self.baseURL.appendingPathComponent("shownew").newsprintAppending(queryItems: [
            URLQueryItem(name: "p", value: "\(page)")
        ])
    }

    private static func resolvedURL(from rawURL: String, fallbackThreadURL: URL) -> URL {
        if rawURL.hasPrefix("item?") {
            return fallbackThreadURL
        }
        if let url = URL(string: rawURL, relativeTo: baseURL)?.absoluteURL {
            return url
        }
        return fallbackThreadURL
    }

    private static func postedAt(from subtext: String) -> Date? {
        guard let title = firstCapture(#"class=['"]age['"]\s+title=['"]([^'"]+)['"]"#, in: subtext) else {
            return nil
        }
        if let timestamp = title.split(separator: " ").last.flatMap({ TimeInterval($0) }) {
            return Date(timeIntervalSince1970: timestamp)
        }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: String(title.prefix(19)))
    }

    private static func commentCount(from subtext: String) -> Int {
        firstInt(#">(\d+)(?:&nbsp;|\s+)comments?</a>"#, in: subtext) ?? 0
    }

    private static func firstInt(_ pattern: String, in text: String) -> Int? {
        firstCapture(pattern, in: text).flatMap(Int.init)
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        matches(for: pattern, in: text).first?.dropFirst().first
    }

    private static func matches(for pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else {
                    return nil
                }
                return String(text[range])
            }
        }
    }
}

private extension URL {
    func newsprintAppending(queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        return components.url!
    }
}
