import Foundation

public enum FeedRefreshOrigin: String, Codable, Sendable {
    case manual
    case automatic
}

public enum FeedRefreshApplicationPolicy {
    public static func shouldDefer(origin: FeedRefreshOrigin, isArticleFeedVisible: Bool) -> Bool {
        origin == .automatic && isArticleFeedVisible
    }
}

public struct FeedRefreshEvent: Sendable, Equatable {
    public let summary: FeedRefreshSummary
    public let origin: FeedRefreshOrigin

    public init(summary: FeedRefreshSummary, origin: FeedRefreshOrigin) {
        self.summary = summary
        self.origin = origin
    }
}

public extension FeedRefreshSummary {
    var hasFeedChanges: Bool {
        insertedCount > 0 || retentionDeletedCount > 0
    }
}
