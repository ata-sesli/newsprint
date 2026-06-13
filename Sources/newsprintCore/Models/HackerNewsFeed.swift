import Foundation

public enum HackerNewsFeedKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case frontPage
    case newest
    case best
    case active
    case show
    case ask
    case jobs
    case launches
    case classic
    case whoIsHiring

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .frontPage:
            "Front Page"
        case .newest:
            "Newest"
        case .best:
            "Best"
        case .active:
            "Active"
        case .show:
            "Show HN"
        case .ask:
            "Ask HN"
        case .jobs:
            "Jobs"
        case .launches:
            "Launches"
        case .classic:
            "Classic"
        case .whoIsHiring:
            "Who is Hiring"
        }
    }

    var pathComponent: String {
        switch self {
        case .frontPage:
            "frontpage"
        case .newest:
            "newest"
        case .best:
            "best"
        case .active:
            "active"
        case .show:
            "show"
        case .ask:
            "ask"
        case .jobs:
            "jobs"
        case .launches:
            "launches"
        case .classic:
            "classic"
        case .whoIsHiring:
            "whoishiring"
        }
    }

    var sourceTitleName: String {
        switch self {
        case .show:
            "Show"
        case .ask:
            "Ask"
        default:
            displayName
        }
    }
}

public struct HackerNewsFeedConfiguration: Equatable, Sendable {
    public var kind: HackerNewsFeedKind
    public var minimumPoints: Int?
    public var minimumComments: Int?
    public var searchQuery: String?
    public var count: Int?

    public init(
        kind: HackerNewsFeedKind,
        minimumPoints: Int? = nil,
        minimumComments: Int? = nil,
        searchQuery: String? = nil,
        count: Int? = nil
    ) {
        self.kind = kind
        self.minimumPoints = minimumPoints
        self.minimumComments = minimumComments
        self.searchQuery = searchQuery
        self.count = count
    }
}

public enum HackerNewsFeedURLBuilder {
    public static func url(for configuration: HackerNewsFeedConfiguration) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "hnrss.org"
        components.path = "/\(configuration.kind.pathComponent)"

        var queryItems: [URLQueryItem] = []
        if let query = configuration.searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
           !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if let minimumPoints = configuration.minimumPoints, minimumPoints > 0 {
            queryItems.append(URLQueryItem(name: "points", value: "\(minimumPoints)"))
        }
        if let minimumComments = configuration.minimumComments, minimumComments > 0 {
            queryItems.append(URLQueryItem(name: "comments", value: "\(minimumComments)"))
        }
        if let count = configuration.count {
            queryItems.append(URLQueryItem(name: "count", value: "\(clampedCount(count))"))
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    public static func title(for configuration: HackerNewsFeedConfiguration) -> String {
        var parts = ["Hacker News \(configuration.kind.sourceTitleName)"]
        if let minimumPoints = configuration.minimumPoints, minimumPoints > 0 {
            parts.append("\(minimumPoints)+ points")
        }
        if let minimumComments = configuration.minimumComments, minimumComments > 0 {
            parts.append("\(minimumComments)+ comments")
        }
        if let query = configuration.searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
           !query.isEmpty {
            parts.append("\"\(query)\"")
        }
        return parts.joined(separator: ", ")
    }

    private static func clampedCount(_ count: Int) -> Int {
        min(100, max(20, count))
    }
}
