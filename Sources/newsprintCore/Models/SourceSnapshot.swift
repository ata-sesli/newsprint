import Foundation

public struct SourceSnapshot: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let url: URL
    public let kind: SourceKind
    public let etag: String?
    public let lastModified: String?

    public init(
        id: UUID,
        title: String,
        url: URL,
        kind: SourceKind,
        etag: String? = nil,
        lastModified: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.kind = kind
        self.etag = etag
        self.lastModified = lastModified
    }
}

public extension SourceSnapshot {
    init(source: Source) {
        self.init(
            id: source.id,
            title: source.title,
            url: source.url,
            kind: source.kind,
            etag: source.etag,
            lastModified: source.lastModified
        )
    }
}
