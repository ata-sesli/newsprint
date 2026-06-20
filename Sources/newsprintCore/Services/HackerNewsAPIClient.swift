import Foundation

public struct HackerNewsItem: Decodable, Equatable, Sendable {
    public let id: Int
    public let type: String?
    public let by: String?
    public let time: TimeInterval?
    public let title: String?
    public let url: URL?
    public let text: String?
    public let score: Int?
    public let descendants: Int?
    public let deleted: Bool?
    public let dead: Bool?
}

public enum HackerNewsAPIError: Error, LocalizedError {
    case invalidSourceURL(URL)
    case invalidItemList

    public var errorDescription: String? {
        switch self {
        case .invalidSourceURL(let url):
            "Invalid Hacker News source URL: \(url.absoluteString)"
        case .invalidItemList:
            "Invalid Hacker News item list"
        }
    }
}

public struct HackerNewsAPIClient: Sendable {
    private static let itemRequestConcurrency = 10
    private let httpClient: FeedHTTPClient

    public init(httpClient: FeedHTTPClient = FeedHTTPClient()) {
        self.httpClient = httpClient
    }

    public func fetchDrafts(
        for source: SourceSnapshot,
        timeout: TimeInterval = FeedHTTPClient.sourceRefreshTimeout
    ) async throws -> [ArticleDraft] {
        guard let configuration = HackerNewsFeedURLBuilder.configuration(from: source.url) else {
            throw HackerNewsAPIError.invalidSourceURL(source.url)
        }

        let totalStartedAt = Date()
        let itemIDs = try await fetchItemIDs(for: configuration, timeout: timeout)
        let wantedCount = HackerNewsFeedURLBuilder.effectiveCount(for: configuration)
        var drafts: [ArticleDraft] = []
        var fetchedItems = 0
        var skippedItems = 0
        let itemsStartedAt = Date()

        var nextIndex = 0
        while drafts.count < wantedCount && nextIndex < itemIDs.count {
            let remainingAcceptedCapacity = wantedCount - drafts.count
            let chunkCount = min(Self.itemRequestConcurrency, remainingAcceptedCapacity, itemIDs.count - nextIndex)
            let chunkIDs = Array(itemIDs[nextIndex..<(nextIndex + chunkCount)])
            nextIndex += chunkCount

            let items = try await BoundedTaskGroup.throwingMap(chunkIDs, limit: chunkCount) { itemID in
                try await fetchItem(id: itemID, timeout: timeout)
            }
            fetchedItems += chunkIDs.count

            for item in items {
                guard drafts.count < wantedCount else {
                    break
                }

                guard let item else {
                    skippedItems += 1
                    continue
                }

                guard include(item, configuration: configuration),
                      let draft = HackerNewsArticleMapper.draft(from: item, source: source) else {
                    skippedItems += 1
                    continue
                }
                drafts.append(draft)
            }
        }

        NewsprintLog.network.info(
            "HN fetch \(source.title, privacy: .public): kind=\(configuration.kind.rawValue, privacy: .public), ids=\(itemIDs.count), itemRequests=\(fetchedItems), skipped=\(skippedItems), drafts=\(drafts.count), itemLoop=\(elapsedMilliseconds(since: itemsStartedAt), format: .fixed(precision: 1))ms, total=\(elapsedMilliseconds(since: totalStartedAt), format: .fixed(precision: 1))ms"
        )
        return drafts
    }

    private func fetchItemIDs(for configuration: HackerNewsFeedConfiguration, timeout: TimeInterval) async throws -> [Int] {
        let startedAt = Date()
        let response = try await httpClient.fetch(
            url: listURL(for: configuration.kind),
            timeout: timeout
        )
        guard let itemIDs = try JSONSerialization.jsonObject(with: response.data) as? [Int] else {
            throw HackerNewsAPIError.invalidItemList
        }
        NewsprintLog.network.info(
            "HN list \(configuration.kind.rawValue, privacy: .public): ids=\(itemIDs.count), elapsed=\(elapsedMilliseconds(since: startedAt), format: .fixed(precision: 1))ms"
        )
        return itemIDs
    }

    private func fetchItem(id: Int, timeout: TimeInterval) async throws -> HackerNewsItem? {
        let response = try await httpClient.fetch(
            url: itemURL(id: id),
            timeout: timeout
        )
        let item = try JSONDecoder().decode(HackerNewsItem.self, from: response.data)
        if item.deleted == true || item.dead == true {
            return nil
        }
        return item
    }

    private func include(_ item: HackerNewsItem, configuration: HackerNewsFeedConfiguration) -> Bool {
        if let minimumPoints = configuration.minimumPoints,
           (item.score ?? 0) < minimumPoints {
            return false
        }
        if let minimumComments = configuration.minimumComments,
           (item.descendants ?? 0) < minimumComments {
            return false
        }
        return true
    }

    private func listURL(for kind: HackerNewsFeedKind) -> URL {
        URL(string: "https://hacker-news.firebaseio.com/v0/\(kind.firebasePathComponent).json")!
    }

    private func itemURL(id: Int) -> URL {
        URL(string: "https://hacker-news.firebaseio.com/v0/item/\(id).json")!
    }

    private func elapsedMilliseconds(since start: Date) -> Double {
        Date().timeIntervalSince(start) * 1_000
    }
}

public enum HackerNewsArticleMapper {
    public static func draft(from item: HackerNewsItem, source: SourceSnapshot) -> ArticleDraft? {
        guard let title = item.title?.trimmedOptional else {
            return nil
        }

        let threadURL = URL(string: "https://news.ycombinator.com/item?id=\(item.id)")!
        let articleURL = item.url ?? threadURL
        let authorText = HTMLTextExtractor.text(fromHTML: item.text)?.trimmedOptional
        let metadata = metadataText(
            articleURL: articleURL,
            threadURL: threadURL,
            points: item.score ?? 0,
            comments: item.descendants ?? 0,
            authorText: authorText
        )

        return ArticleDraft(
            sourceID: source.id,
            sourceTitle: source.title,
            title: title,
            url: articleURL,
            author: item.by?.trimmedOptional,
            publishedAt: item.time.map { Date(timeIntervalSince1970: $0) },
            updatedAt: nil,
            excerpt: authorText,
            contentHTML: item.text,
            contentText: metadata,
            externalID: "hn:\(item.id)"
        )
    }

    private static func metadataText(
        articleURL: URL,
        threadURL: URL,
        points: Int,
        comments: Int,
        authorText: String?
    ) -> String {
        var text = "Article URL: \(articleURL.absoluteString) Comments URL: \(threadURL.absoluteString) Points: \(points) # Comments: \(comments)"
        if let authorText, !authorText.isEmpty {
            text += " \(authorText)"
        }
        return text
    }
}

private extension String {
    var trimmedOptional: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
