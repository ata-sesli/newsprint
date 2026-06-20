import Foundation
import Testing
@testable import newsprintCore

@Test func feedHTTPClientUsesFourSecondTimeoutForFastSourceRefresh() async throws {
    TimeoutCapturingURLProtocol.lastTimeout = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TimeoutCapturingURLProtocol.self]
    let client = FeedHTTPClient(session: URLSession(configuration: configuration))
    let source = SourceSnapshot(
        id: UUID(),
        title: "Example",
        url: try #require(URL(string: "https://example.com/feed.xml")),
        kind: .rss
    )

    _ = try await client.fetch(source: source)

    #expect(TimeoutCapturingURLProtocol.lastTimeout == 4)
}

private final class TimeoutCapturingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastTimeout: TimeInterval?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastTimeout = request.timeoutInterval
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("<rss><channel><title>Example</title></channel></rss>".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
