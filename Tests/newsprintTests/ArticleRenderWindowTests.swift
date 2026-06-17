import Testing
import newsprintCore

@Suite("Article render window")
struct ArticleRenderWindowTests {
    @Test("Initial window exposes at most 150 items")
    func initialWindowRange() {
        let window = ArticleRenderWindow()

        #expect(window.range(totalCount: 750) == 0..<150)
        #expect(window.range(totalCount: 90) == 0..<90)
    }

    @Test("Window shifts down at local index 100")
    func shiftsDownAtThreshold() {
        let window = ArticleRenderWindow()
        let shifted = window.shiftedIfNeeded(localIndex: 100, totalCount: 750)

        #expect(shifted.start == 50)
        #expect(shifted.range(totalCount: 750) == 50..<200)
    }

    @Test("Window shifts up at local index 49")
    func shiftsUpAtThreshold() {
        let window = ArticleRenderWindow(start: 100)
        let shifted = window.shiftedIfNeeded(localIndex: 49, totalCount: 750)

        #expect(shifted.start == 50)
        #expect(shifted.range(totalCount: 750) == 50..<200)
    }

    @Test("Window clamps at collection edges")
    func clampsAtEdges() {
        let nearEnd = ArticleRenderWindow(start: 600).shiftedIfNeeded(localIndex: 100, totalCount: 700)
        let atStart = ArticleRenderWindow(start: 0).shiftedIfNeeded(localIndex: 49, totalCount: 700)

        #expect(nearEnd.start == 550)
        #expect(atStart.start == 0)
    }

    @Test("Density collapsed heights are fixed")
    func collapsedHeights() {
        #expect(ArticleListDensity.compact.collapsedCardHeight == 112)
        #expect(ArticleListDensity.comfortable.collapsedCardHeight == 164)
        #expect(ArticleListDensity.newspaper.collapsedCardHeight == 236)
    }

    @Test("Edge reporter only reports the same edge once until reset")
    func edgeReporterDeduplicatesRepeatedEdges() {
        var reporter = ArticleRenderWindowEdgeReporter()

        let first = reporter.report(
            firstVisible: 0,
            lastVisible: 12,
            itemCount: 150,
            loadMoreThreshold: 50
        )
        let repeated = reporter.report(
            firstVisible: 4,
            lastVisible: 18,
            itemCount: 150,
            loadMoreThreshold: 50
        )

        #expect(first?.edge == .shiftUp)
        #expect(first?.localIndex == 0)
        #expect(repeated == nil)

        reporter.reset()

        let afterReset = reporter.report(
            firstVisible: 8,
            lastVisible: 20,
            itemCount: 150,
            loadMoreThreshold: 50
        )

        #expect(afterReset?.edge == .shiftUp)
        #expect(afterReset?.localIndex == 8)
    }

    @Test("Edge reporter reports load more before window shifts")
    func edgeReporterPrioritizesLoadMore() {
        var reporter = ArticleRenderWindowEdgeReporter()

        let report = reporter.report(
            firstVisible: 110,
            lastVisible: 149,
            itemCount: 150,
            loadMoreThreshold: 50
        )

        #expect(report?.edge == .loadMore)
        #expect(report?.localIndex == 149)
    }

    @Test("Edge reporter allows the same edge after backing data generation changes")
    func edgeReporterAllowsSameEdgeAfterGenerationChange() {
        var reporter = ArticleRenderWindowEdgeReporter()

        let first = reporter.report(
            firstVisible: 110,
            lastVisible: 149,
            itemCount: 150,
            loadMoreThreshold: 50,
            generation: 0
        )
        let repeated = reporter.report(
            firstVisible: 112,
            lastVisible: 149,
            itemCount: 150,
            loadMoreThreshold: 50,
            generation: 0
        )
        let afterAppend = reporter.report(
            firstVisible: 112,
            lastVisible: 149,
            itemCount: 150,
            loadMoreThreshold: 50,
            generation: 1
        )

        #expect(first?.edge == .loadMore)
        #expect(repeated == nil)
        #expect(afterAppend?.edge == .loadMore)
        #expect(afterAppend?.localIndex == 149)
    }
}
