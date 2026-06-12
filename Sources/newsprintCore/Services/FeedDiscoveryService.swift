import Foundation

public enum DiscoveredFeedType: String, Codable, Hashable, Sendable {
    case rss
    case atom
    case jsonFeed

    public var sourceKind: SourceKind {
        switch self {
        case .rss: .rss
        case .atom: .atom
        case .jsonFeed: .jsonFeed
        }
    }
}

public struct DiscoveredFeed: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String?
    public let url: URL
    public let type: DiscoveredFeedType

    public init(id: UUID = UUID(), title: String?, url: URL, type: DiscoveredFeedType) {
        self.id = id
        self.title = title
        self.url = url
        self.type = type
    }
}

public enum FeedDiscoveryResult: Equatable, Sendable {
    case directFeed(DiscoveredFeed)
    case candidates([DiscoveredFeed])
}

public enum FeedDiscoveryError: Error, Equatable, LocalizedError, Sendable {
    case noFeedsFound

    public var errorDescription: String? {
        switch self {
        case .noFeedsFound: "No feed was found at that URL."
        }
    }
}

@MainActor
public protocol FeedDiscoveryFetching {
    func fetch(url: URL) async throws -> Data
}

@MainActor
public struct FeedHTTPDiscoveryFetcher: FeedDiscoveryFetching {
    private let client: FeedHTTPClient

    public init(client: FeedHTTPClient = FeedHTTPClient()) {
        self.client = client
    }

    public func fetch(url: URL) async throws -> Data {
        try await client.fetch(url: url).data
    }
}

@MainActor
public struct FeedDiscoveryService {
    private let fetcher: FeedDiscoveryFetching
    private let parser: FeedParser

    public init(
        fetcher: FeedDiscoveryFetching = FeedHTTPDiscoveryFetcher(),
        parser: FeedParser = FeedParser()
    ) {
        self.fetcher = fetcher
        self.parser = parser
    }

    public func discover(from url: URL) async throws -> FeedDiscoveryResult {
        let initialData = try await fetcher.fetch(url: url)

        if let type = feedType(for: initialData), canParseFeed(data: initialData, url: url, type: type) {
            return .directFeed(DiscoveredFeed(title: nil, url: url, type: type))
        }

        let html = String(data: initialData, encoding: .utf8) ?? ""
        let alternateFeeds = deduplicated(parseAlternateLinks(in: html, pageURL: url))
        if !alternateFeeds.isEmpty {
            return .candidates(alternateFeeds)
        }

        let probedFeeds = await probeCommonPaths(from: url)
        if !probedFeeds.isEmpty {
            return .candidates(deduplicated(probedFeeds))
        }

        throw FeedDiscoveryError.noFeedsFound
    }

    private func probeCommonPaths(from url: URL) async -> [DiscoveredFeed] {
        let paths = ["/feed", "/rss", "/rss.xml", "/atom.xml", "/feed.xml", "/index.xml"]
        var feeds: [DiscoveredFeed] = []

        for path in paths {
            guard let probeURL = originURL(for: url, path: path),
                  let data = try? await fetcher.fetch(url: probeURL),
                  let type = feedType(for: data),
                  canParseFeed(data: data, url: probeURL, type: type) else {
                continue
            }

            feeds.append(DiscoveredFeed(title: nil, url: probeURL, type: type))
        }

        return feeds
    }

    private func parseAlternateLinks(in html: String, pageURL: URL) -> [DiscoveredFeed] {
        let pattern = #"<link\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: html) else { return nil }
            let tag = String(html[range])
            let attributes = parseAttributes(in: tag)

            guard attributes["rel"]?.lowercased().split(separator: " ").contains("alternate") == true,
                  let type = feedType(forMimeType: attributes["type"]),
                  let href = attributes["href"],
                  let resolvedURL = URL(string: href, relativeTo: pageURL)?.absoluteURL else {
                return nil
            }

            return DiscoveredFeed(
                title: attributes["title"],
                url: resolvedURL,
                type: type
            )
        }
    }

    private func parseAttributes(in tag: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(['"])(.*?)\2"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [:]
        }

        let nsRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var attributes: [String: String] = [:]

        for match in regex.matches(in: tag, range: nsRange) {
            guard let keyRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 3), in: tag) else {
                continue
            }
            attributes[String(tag[keyRange]).lowercased()] = String(tag[valueRange])
        }

        return attributes
    }

    private func feedType(forMimeType mimeType: String?) -> DiscoveredFeedType? {
        guard let mimeType = mimeType?.lowercased() else { return nil }

        if mimeType.contains("rss") {
            return .rss
        }

        if mimeType.contains("atom") {
            return .atom
        }

        if mimeType.contains("feed+json") || mimeType.contains("json") {
            return .jsonFeed
        }

        return nil
    }

    private func feedType(for data: Data) -> DiscoveredFeedType? {
        if data.firstNonWhitespaceByteForDiscovery == UInt8(ascii: "{") {
            return .jsonFeed
        }

        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        if text.range(of: "<rss", options: .caseInsensitive) != nil {
            return .rss
        }

        if text.range(of: "<feed", options: .caseInsensitive) != nil {
            return .atom
        }

        return nil
    }

    private func canParseFeed(data: Data, url: URL, type: DiscoveredFeedType) -> Bool {
        let source = Source(
            title: url.host() ?? url.absoluteString,
            url: url,
            kind: type.sourceKind
        )
        return (try? parser.parse(data: data, source: source)) != nil
    }

    private func originURL(for url: URL, path: String) -> URL? {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host()
        components.port = url.port
        components.path = path
        return components.url
    }

    private func deduplicated(_ feeds: [DiscoveredFeed]) -> [DiscoveredFeed] {
        var seen = Set<String>()
        var result: [DiscoveredFeed] = []

        for feed in feeds {
            let key = URLCanonicalizer.canonicalize(feed.url).absoluteString
            guard seen.insert(key).inserted else {
                continue
            }
            result.append(feed)
        }

        return result
    }
}

private extension Data {
    var firstNonWhitespaceByteForDiscovery: UInt8? {
        first { byte in
            byte != UInt8(ascii: " ") &&
            byte != UInt8(ascii: "\n") &&
            byte != UInt8(ascii: "\r") &&
            byte != UInt8(ascii: "\t")
        }
    }
}

