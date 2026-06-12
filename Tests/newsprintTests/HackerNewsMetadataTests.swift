import Foundation
import Testing
@testable import newsprintCore

@Test func parsesHackerNewsRSSMetadata() throws {
    let text = "Article URL: https://interkom.app/ Comments URL: https://news.ycombinator.com/item?id=48500866 Points: 1 # Comments: 0"

    let metadata = try #require(HackerNewsMetadata(text: text))

    #expect(metadata.articleURL?.absoluteString == "https://interkom.app/")
    #expect(metadata.threadURL?.absoluteString == "https://news.ycombinator.com/item?id=48500866")
    #expect(metadata.points == 1)
    #expect(metadata.commentCount == 0)
    #expect(metadata.authorComment == nil)
}

@Test func parsesHackerNewsAuthorCommentWithoutRawMetadata() throws {
    let text = "Article URL: https://example.com Comments URL: https://news.ycombinator.com/item?id=1 Points: 42 # Comments: 3 I built this over the weekend to make RSS calmer."

    let metadata = try #require(HackerNewsMetadata(text: text))

    #expect(metadata.authorComment == "I built this over the weekend to make RSS calmer.")
}

