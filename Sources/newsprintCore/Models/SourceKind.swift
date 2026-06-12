import Foundation

public enum SourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case rss
    case atom
    case jsonFeed
    case youtube
    case hackerNews
    case blog

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rss: "RSS"
        case .atom: "Atom"
        case .jsonFeed: "JSON Feed"
        case .youtube: "YouTube"
        case .hackerNews: "Hacker News"
        case .blog: "Blog"
        }
    }
}
