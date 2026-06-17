import Foundation

public struct ArticleRenderWindow: Equatable, Sendable {
    public static let defaultSize = 150
    public static let defaultStride = 50
    public static let shiftDownLocalIndex = 100
    public static let shiftUpLocalIndex = 49

    public let start: Int
    public let size: Int
    public let stride: Int

    public init(start: Int = 0, size: Int = Self.defaultSize, stride: Int = Self.defaultStride) {
        self.start = max(0, start)
        self.size = max(1, size)
        self.stride = max(1, stride)
    }

    public var end: Int {
        start + size
    }

    public func range(totalCount: Int) -> Range<Int> {
        let lower = min(start, max(0, totalCount))
        let upper = min(lower + size, max(0, totalCount))
        return lower..<upper
    }

    public func globalIndex(forLocalIndex localIndex: Int) -> Int {
        start + max(0, localIndex)
    }

    public func shiftedIfNeeded(localIndex: Int, totalCount: Int) -> ArticleRenderWindow {
        let maxStart = max(0, totalCount - size)
        if localIndex >= Self.shiftDownLocalIndex {
            return ArticleRenderWindow(
                start: min(start + stride, maxStart),
                size: size,
                stride: stride
            )
        }

        if localIndex <= Self.shiftUpLocalIndex, start > 0 {
            return ArticleRenderWindow(
                start: max(0, start - stride),
                size: size,
                stride: stride
            )
        }

        return self
    }
}

public enum ArticleRenderWindowEdge: Equatable, Sendable {
    case loadMore
    case shiftDown
    case shiftUp
}

public struct ArticleRenderWindowEdgeReport: Equatable, Sendable {
    public let edge: ArticleRenderWindowEdge
    public let localIndex: Int

    public init(edge: ArticleRenderWindowEdge, localIndex: Int) {
        self.edge = edge
        self.localIndex = localIndex
    }
}

public struct ArticleRenderWindowEdgeReporter: Equatable, Sendable {
    private struct ReportKey: Equatable, Sendable {
        let edge: ArticleRenderWindowEdge
        let generation: Int
    }

    private var lastReportedKey: ReportKey?

    public init() {}

    public mutating func report(
        firstVisible: Int,
        lastVisible: Int,
        itemCount: Int,
        loadMoreThreshold: Int,
        generation: Int = 0
    ) -> ArticleRenderWindowEdgeReport? {
        guard itemCount > 0 else {
            return nil
        }

        let report: ArticleRenderWindowEdgeReport?
        if lastVisible >= max(0, itemCount - loadMoreThreshold) {
            report = ArticleRenderWindowEdgeReport(edge: .loadMore, localIndex: lastVisible)
        } else if lastVisible >= ArticleRenderWindow.shiftDownLocalIndex {
            report = ArticleRenderWindowEdgeReport(edge: .shiftDown, localIndex: lastVisible)
        } else if firstVisible <= ArticleRenderWindow.shiftUpLocalIndex {
            report = ArticleRenderWindowEdgeReport(edge: .shiftUp, localIndex: firstVisible)
        } else {
            report = nil
        }

        guard let report else {
            return nil
        }
        let key = ReportKey(edge: report.edge, generation: generation)
        guard key != lastReportedKey else {
            return nil
        }

        lastReportedKey = key
        return report
    }

    public mutating func reset() {
        lastReportedKey = nil
    }
}
