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
    private static let itemRequestTimeout: TimeInterval = 4
    private static let showNewPageLimit = 3
    private let httpClient: FeedHTTPClient
    private let pageClient: HackerNewsPageClient

    public init(httpClient: FeedHTTPClient = FeedHTTPClient()) {
        self.httpClient = httpClient
        self.pageClient = HackerNewsPageClient(httpClient: httpClient)
    }

    public func fetchDrafts(
        for source: SourceSnapshot,
        timeout: TimeInterval = FeedHTTPClient.sourceRefreshTimeout
    ) async throws -> [ArticleDraft] {
        guard let configuration = HackerNewsFeedURLBuilder.configuration(from: source.url) else {
            throw HackerNewsAPIError.invalidSourceURL(source.url)
        }

        let totalStartedAt = Date()
        if configuration.kind == .show {
            return try await fetchShowNewDrafts(
                configuration: configuration,
                source: source,
                timeout: timeout,
                startedAt: totalStartedAt
            )
        }

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
                try await fetchItem(id: itemID, timeout: Self.itemRequestTimeout)
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

    private func fetchShowNewDrafts(
        configuration: HackerNewsFeedConfiguration,
        source: SourceSnapshot,
        timeout: TimeInterval,
        startedAt totalStartedAt: Date
    ) async throws -> [ArticleDraft] {
        let wantedCount = HackerNewsFeedURLBuilder.effectiveCount(for: configuration)
        var drafts: [ArticleDraft] = []
        var page = 1
        var fetchedPages = 0
        var fetchedItems = 0
        var skippedItems = 0
        let itemsStartedAt = Date()

        while drafts.count < wantedCount && page <= Self.showNewPageLimit {
            let hnPage = try await pageClient.fetchShowNewPage(page: page, timeout: timeout)
            fetchedPages += 1
            let pageItems = hnPage.items
            var nextIndex = 0

            while drafts.count < wantedCount && nextIndex < pageItems.count {
                let remainingAcceptedCapacity = wantedCount - drafts.count
                let remainingPageCount = pageItems.count - nextIndex
                let chunkCount = min(Self.itemRequestConcurrency, remainingAcceptedCapacity, remainingPageCount)
                let chunk = Array(pageItems[nextIndex..<(nextIndex + chunkCount)])
                nextIndex += chunkCount

                let items = await BoundedTaskGroup.map(chunk, limit: chunkCount) { pageItem in
                    try? await fetchItem(id: pageItem.id, timeout: Self.itemRequestTimeout)
                }
                fetchedItems += chunk.count

                for (pageItem, item) in zip(chunk, items) {
                    guard drafts.count < wantedCount else {
                        break
                    }

                    guard let item else {
                        skippedItems += 1
                        continue
                    }

                    guard include(item, pageItem: pageItem, configuration: configuration),
                          let draft = HackerNewsArticleMapper.draft(from: item, pageItem: pageItem, source: source) else {
                        skippedItems += 1
                        continue
                    }
                    drafts.append(draft)
                }
            }

            guard drafts.count < wantedCount,
                  let nextPage = hnPage.nextPage,
                  nextPage > page else {
                break
            }
            page = nextPage
        }

        NewsprintLog.network.info(
            "HN shownew fetch \(source.title, privacy: .public): pages=\(fetchedPages), itemRequests=\(fetchedItems), skipped=\(skippedItems), drafts=\(drafts.count), itemLoop=\(elapsedMilliseconds(since: itemsStartedAt), format: .fixed(precision: 1))ms, total=\(elapsedMilliseconds(since: totalStartedAt), format: .fixed(precision: 1))ms"
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
        include(item, pageItem: nil, configuration: configuration)
    }

    private func include(_ item: HackerNewsItem, pageItem: HackerNewsPageItem?, configuration: HackerNewsFeedConfiguration) -> Bool {
        if let minimumPoints = configuration.minimumPoints,
           (item.score ?? pageItem?.points ?? 0) < minimumPoints {
            return false
        }
        if let minimumComments = configuration.minimumComments,
           (item.descendants ?? pageItem?.commentCount ?? 0) < minimumComments {
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
        draft(from: item, pageItem: nil, source: source)
    }

    public static func draft(from item: HackerNewsItem, pageItem: HackerNewsPageItem?, source: SourceSnapshot) -> ArticleDraft? {
        guard let title = item.title?.trimmedOptional ?? pageItem?.title.trimmedOptional else {
            return nil
        }

        let threadURL = URL(string: "https://news.ycombinator.com/item?id=\(item.id)")!
        let articleURL = item.url ?? pageItem?.url ?? threadURL
        let authorText = HTMLTextExtractor.text(fromHTML: item.text)?.trimmedOptional
        let metadata = metadataText(
            articleURL: articleURL,
            threadURL: threadURL,
            points: item.score ?? pageItem?.points ?? 0,
            comments: item.descendants ?? pageItem?.commentCount ?? 0,
            authorText: authorText
        )

        return ArticleDraft(
            sourceID: source.id,
            sourceTitle: source.title,
            title: title,
            url: articleURL,
            author: item.by?.trimmedOptional ?? pageItem?.author?.trimmedOptional,
            publishedAt: item.time.map { Date(timeIntervalSince1970: $0) } ?? pageItem?.postedAt,
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
