import Foundation
import Testing
@testable import newsprintCore

@Test func hackerNewsFrontPageBuildsBaseFeedURL() {
    let configuration = HackerNewsFeedConfiguration(kind: .frontPage)

    #expect(HackerNewsFeedURLBuilder.url(for: configuration).absoluteString == "https://hnrss.org/frontpage")
    #expect(HackerNewsFeedURLBuilder.title(for: configuration) == "Hacker News Front Page")
}

@Test func hackerNewsShowWithPointsBuildsTunedFeedURL() {
    let configuration = HackerNewsFeedConfiguration(kind: .show, minimumPoints: 50)

    #expect(HackerNewsFeedURLBuilder.url(for: configuration).absoluteString == "https://hnrss.org/show?points=50")
    #expect(HackerNewsFeedURLBuilder.title(for: configuration) == "Hacker News Show, 50+ points")
}

@Test func hackerNewsAskWithCommentsBuildsTunedFeedURL() {
    let configuration = HackerNewsFeedConfiguration(kind: .ask, minimumComments: 25)

    #expect(HackerNewsFeedURLBuilder.url(for: configuration).absoluteString == "https://hnrss.org/ask?comments=25")
}

@Test func hackerNewsNewestWithQueryAndCountBuildsStableEncodedParams() {
    let configuration = HackerNewsFeedConfiguration(kind: .newest, searchQuery: "React Native", count: 50)

    #expect(HackerNewsFeedURLBuilder.url(for: configuration).absoluteString == "https://hnrss.org/newest?q=React%20Native&count=50")
}

@Test func hackerNewsCountClampsToHNRSSLimit() {
    let configuration = HackerNewsFeedConfiguration(kind: .active, count: 250)

    #expect(HackerNewsFeedURLBuilder.url(for: configuration).absoluteString == "https://hnrss.org/active?count=100")
}
