import Foundation
import Testing
@testable import newsprintCore

@Test func hackerNewsFrontPageBuildsBaseFeedURL() {
    let configuration = HackerNewsFeedConfiguration(kind: .frontPage)

    #expect(HackerNewsFeedURLBuilder.url(for: configuration).absoluteString == "https://hacker-news.firebaseio.com/v0/topstories.json")
    #expect(HackerNewsFeedURLBuilder.title(for: configuration) == "Hacker News Front Page")
}

@Test func hackerNewsShowWithPointsBuildsTunedFeedURL() {
    let configuration = HackerNewsFeedConfiguration(kind: .show, minimumPoints: 50)

    #expect(HackerNewsFeedURLBuilder.url(for: configuration).absoluteString == "https://hacker-news.firebaseio.com/v0/showstories.json?points=50")
    #expect(HackerNewsFeedURLBuilder.title(for: configuration) == "Hacker News Show, 50+ points")
}

@Test func hackerNewsAskWithCommentsBuildsTunedFeedURL() {
    let configuration = HackerNewsFeedConfiguration(kind: .ask, minimumComments: 25)

    #expect(HackerNewsFeedURLBuilder.url(for: configuration).absoluteString == "https://hacker-news.firebaseio.com/v0/askstories.json?comments=25")
}

@Test func hackerNewsNewestWithCountBuildsStableParams() {
    let configuration = HackerNewsFeedConfiguration(kind: .newest, count: 50)

    #expect(HackerNewsFeedURLBuilder.url(for: configuration).absoluteString == "https://hacker-news.firebaseio.com/v0/newstories.json?count=50")
}

@Test func hackerNewsCountClampsToFirebaseLocalLimit() {
    let configuration = HackerNewsFeedConfiguration(kind: .show, count: 250)

    #expect(HackerNewsFeedURLBuilder.url(for: configuration).absoluteString == "https://hacker-news.firebaseio.com/v0/showstories.json?count=200")
    #expect(HackerNewsFeedURLBuilder.effectiveCount(for: configuration) == 200)
}

@Test func legacyHNRSSShowURLParsesAsFirebaseConfiguration() throws {
    let url = try #require(URL(string: "https://hnrss.org/show?points=50&count=100"))
    let configuration = try #require(HackerNewsFeedURLBuilder.configuration(from: url))

    #expect(configuration.kind == .show)
    #expect(configuration.minimumPoints == 50)
    #expect(configuration.count == 100)
}

@Test func unsupportedLegacyHNRSSKindDoesNotParse() throws {
    let url = try #require(URL(string: "https://hnrss.org/active"))

    #expect(HackerNewsFeedURLBuilder.configuration(from: url) == nil)
}
