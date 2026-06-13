import Foundation

public struct TodaySummary {
    public let todayCount: Int
    public let unreadCount: Int
    public let starredCount: Int
    public let hiddenCount: Int
    public let frontPage: [Article]
    public let recentSources: [Source]

    public init(
        todayCount: Int,
        unreadCount: Int,
        starredCount: Int,
        hiddenCount: Int,
        frontPage: [Article],
        recentSources: [Source]
    ) {
        self.todayCount = todayCount
        self.unreadCount = unreadCount
        self.starredCount = starredCount
        self.hiddenCount = hiddenCount
        self.frontPage = frontPage
        self.recentSources = recentSources
    }
}

public struct TodaySummaryBuilder {
    public init() {}

    public func summary(
        articles: [Article],
        sources: [Source],
        now: Date = Date(),
        frontPageLimit: Int = 8,
        recentSourceLimit: Int = 6
    ) -> TodaySummary {
        let startOfToday = Calendar.current.startOfDay(for: now)
        let frontPage = articles
            .filter { !$0.isRead && !$0.isHidden }
            .sorted(by: ranked)
            .prefix(frontPageLimit)

        let recentSources = sources
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastFetchedAt ?? lhs.createdAt
                let rhsDate = rhs.lastFetchedAt ?? rhs.createdAt
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(recentSourceLimit)

        return TodaySummary(
            todayCount: articles.filter { $0.fetchedAt >= startOfToday }.count,
            unreadCount: articles.filter { !$0.isRead }.count,
            starredCount: articles.filter(\.isStarred).count,
            hiddenCount: articles.filter(\.isHidden).count,
            frontPage: Array(frontPage),
            recentSources: Array(recentSources)
        )
    }

    private func ranked(_ lhs: Article, _ rhs: Article) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        let lhsPublished = lhs.publishedAt ?? .distantPast
        let rhsPublished = rhs.publishedAt ?? .distantPast
        if lhsPublished != rhsPublished {
            return lhsPublished > rhsPublished
        }

        return lhs.fetchedAt > rhs.fetchedAt
    }
}
