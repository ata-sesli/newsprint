import Foundation
import SwiftData

@Model
public final class Source {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var url: URL
    public var siteURL: URL?
    public var kindRawValue: String
    public var enabled: Bool
    public var category: String?
    public var lastFetchedAt: Date?
    public var lastSuccessfulFetchAt: Date?
    public var lastErrorMessage: String?
    public var consecutiveFailureCount: Int
    public var etag: String?
    public var lastModified: String?
    public var createdAt: Date
    public var updatedAt: Date

    public var kind: SourceKind {
        get { SourceKind(rawValue: kindRawValue) ?? .rss }
        set { kindRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        siteURL: URL? = nil,
        kind: SourceKind = .rss,
        enabled: Bool = true,
        category: String? = nil,
        lastFetchedAt: Date? = nil,
        lastSuccessfulFetchAt: Date? = nil,
        lastErrorMessage: String? = nil,
        consecutiveFailureCount: Int = 0,
        etag: String? = nil,
        lastModified: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.siteURL = siteURL
        self.kindRawValue = kind.rawValue
        self.enabled = enabled
        self.category = category
        self.lastFetchedAt = lastFetchedAt
        self.lastSuccessfulFetchAt = lastSuccessfulFetchAt
        self.lastErrorMessage = lastErrorMessage
        self.consecutiveFailureCount = consecutiveFailureCount
        self.etag = etag
        self.lastModified = lastModified
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func makeForTests(title: String, url: String, kind: SourceKind) -> Source {
        Source(title: title, url: URL(string: url)!, kind: kind)
    }
}
