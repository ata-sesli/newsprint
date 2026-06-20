import Foundation

public enum HackerNewsFeedKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case frontPage
    case newest
    case best
    case show
    case ask
    case jobs

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .frontPage:
            "Front Page"
        case .newest:
            "Newest"
        case .best:
            "Best"
        case .show:
            "Show HN"
        case .ask:
            "Ask HN"
        case .jobs:
            "Jobs"
        }
    }

    var firebasePathComponent: String {
        switch self {
        case .frontPage:
            "topstories"
        case .newest:
            "newstories"
        case .best:
            "beststories"
        case .show:
            "showstories"
        case .ask:
            "askstories"
        case .jobs:
            "jobstories"
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

    static func fromLegacyHNRSSPath(_ path: String) -> HackerNewsFeedKind? {
        switch path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() {
        case "frontpage":
            return .frontPage
        case "newest":
            return .newest
        case "best":
            return .best
        case "show":
            return .show
        case "ask":
            return .ask
        case "jobs":
            return .jobs
        default:
            return nil
        }
    }

    static func fromFirebasePath(_ path: String) -> HackerNewsFeedKind? {
        let trimmed = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: ".json", with: "")
            .lowercased()
        switch trimmed {
        case "v0/topstories":
            return .frontPage
        case "v0/newstories":
            return .newest
        case "v0/beststories":
            return .best
        case "v0/showstories":
            return .show
        case "v0/askstories":
            return .ask
        case "v0/jobstories":
            return .jobs
        default:
            return nil
        }
    }
}

public struct HackerNewsFeedConfiguration: Equatable, Sendable {
    public var kind: HackerNewsFeedKind
    public var minimumPoints: Int?
    public var minimumComments: Int?
    public var count: Int?

    public init(
        kind: HackerNewsFeedKind,
        minimumPoints: Int? = nil,
        minimumComments: Int? = nil,
        count: Int? = nil
    ) {
        self.kind = kind
        self.minimumPoints = minimumPoints
        self.minimumComments = minimumComments
        self.count = count
    }
}

public enum HackerNewsFeedURLBuilder {
    public static let defaultCount = 30

    public static func url(for configuration: HackerNewsFeedConfiguration) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "hacker-news.firebaseio.com"
        components.path = "/v0/\(configuration.kind.firebasePathComponent).json"

        var queryItems: [URLQueryItem] = []
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
        return parts.joined(separator: ", ")
    }

    public static func configuration(from url: URL) -> HackerNewsFeedConfiguration? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else {
            return nil
        }

        let kind: HackerNewsFeedKind?
        if host == "hacker-news.firebaseio.com" {
            kind = HackerNewsFeedKind.fromFirebasePath(components.path)
        } else if host == "hnrss.org" {
            kind = HackerNewsFeedKind.fromLegacyHNRSSPath(components.path)
        } else {
            kind = nil
        }

        guard let kind else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        return HackerNewsFeedConfiguration(
            kind: kind,
            minimumPoints: positiveInt(named: "points", in: queryItems),
            minimumComments: positiveInt(named: "comments", in: queryItems),
            count: positiveInt(named: "count", in: queryItems)
        )
    }

    public static func effectiveCount(for configuration: HackerNewsFeedConfiguration) -> Int {
        clampedCount(configuration.count ?? defaultCount)
    }

    public static func clampedCount(_ count: Int) -> Int {
        min(200, max(20, count))
    }

    private static func positiveInt(named name: String, in items: [URLQueryItem]) -> Int? {
        guard let value = items.first(where: { $0.name == name })?.value,
              let number = Int(value),
              number > 0 else {
            return nil
        }
        return number
    }
}
