import Foundation

public struct FeedHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let etag: String?
    public let lastModified: String?

    public var isNotModified: Bool { statusCode == 304 }
}

public enum FeedHTTPError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .httpStatus(let code): "HTTP \(code)"
        }
    }
}

public struct FeedHTTPClient: @unchecked Sendable {
    public static let fastSourceRefreshTimeout: TimeInterval = 4
    public static let recoverySourceRefreshTimeout: TimeInterval = 16
    public static let sourceRefreshTimeout: TimeInterval = fastSourceRefreshTimeout
    public static let defaultTimeout: TimeInterval = 20
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(source: Source) async throws -> FeedHTTPResponse {
        try await fetch(source: SourceSnapshot(source: source))
    }

    public func fetch(source: SourceSnapshot) async throws -> FeedHTTPResponse {
        try await fetch(source: source, timeout: Self.sourceRefreshTimeout)
    }

    public func fetch(source: SourceSnapshot, timeout: TimeInterval) async throws -> FeedHTTPResponse {
        try await fetch(
            url: source.url,
            etag: source.etag,
            lastModified: source.lastModified,
            timeout: timeout
        )
    }

    public func fetch(
        url: URL,
        etag: String? = nil,
        lastModified: String? = nil,
        timeout: TimeInterval = Self.defaultTimeout
    ) async throws -> FeedHTTPResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Newsprint/0.1", forHTTPHeaderField: "User-Agent")

        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        if let lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedHTTPError.invalidResponse
        }

        if (400...599).contains(httpResponse.statusCode) {
            throw FeedHTTPError.httpStatus(httpResponse.statusCode)
        }

        return FeedHTTPResponse(
            data: data,
            statusCode: httpResponse.statusCode,
            etag: httpResponse.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
        )
    }
}
