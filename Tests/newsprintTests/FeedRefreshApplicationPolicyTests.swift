import Testing
import newsprintCore

@Suite("Feed refresh application policy")
struct FeedRefreshApplicationPolicyTests {
    @Test("Automatic refresh defers when article feed is visible")
    func automaticRefreshDefersWhenArticleFeedIsVisible() {
        #expect(FeedRefreshApplicationPolicy.shouldDefer(
            origin: .automatic,
            isArticleFeedVisible: true
        ))
    }

    @Test("Manual refresh applies immediately even when article feed is visible")
    func manualRefreshAppliesImmediately() {
        #expect(!FeedRefreshApplicationPolicy.shouldDefer(
            origin: .manual,
            isArticleFeedVisible: true
        ))
    }

    @Test("Automatic refresh applies immediately away from article feed")
    func automaticRefreshAppliesAwayFromFeed() {
        #expect(!FeedRefreshApplicationPolicy.shouldDefer(
            origin: .automatic,
            isArticleFeedVisible: false
        ))
    }
}
