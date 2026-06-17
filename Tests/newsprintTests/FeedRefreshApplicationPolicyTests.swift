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

    @Test("Changed manual refresh shows apply skeleton on visible article feed")
    func changedManualRefreshShowsApplySkeletonOnVisibleArticleFeed() {
        #expect(FeedRefreshApplicationPolicy.shouldShowApplySkeleton(
            origin: .manual,
            isArticleFeedVisible: true,
            summary: FeedRefreshSummary(insertedCount: 1, insertedArticleIDs: ["article-1"])
        ))
    }

    @Test("Unchanged refresh does not show apply skeleton")
    func unchangedRefreshDoesNotShowApplySkeleton() {
        #expect(!FeedRefreshApplicationPolicy.shouldShowApplySkeleton(
            origin: .manual,
            isArticleFeedVisible: true,
            summary: FeedRefreshSummary(skippedCount: 3)
        ))
    }

    @Test("Refresh away from article feed does not show apply skeleton")
    func refreshAwayFromArticleFeedDoesNotShowApplySkeleton() {
        #expect(!FeedRefreshApplicationPolicy.shouldShowApplySkeleton(
            origin: .manual,
            isArticleFeedVisible: false,
            summary: FeedRefreshSummary(insertedCount: 1, insertedArticleIDs: ["article-1"])
        ))
    }
}
