import Testing
@testable import newsprintCore

private struct Candidate: Equatable {
    let id: String
    let score: Double
    let publishedIndex: Int
}

@Test func topCandidateBufferKeepsBestHotCandidates() {
    var buffer = TopCandidateBuffer<Candidate>(
        limit: 3,
        areInPreferredOrder: { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.publishedIndex > rhs.publishedIndex
        }
    )

    [
        Candidate(id: "low", score: 1, publishedIndex: 10),
        Candidate(id: "high-old", score: 9, publishedIndex: 1),
        Candidate(id: "mid", score: 5, publishedIndex: 4),
        Candidate(id: "high-new", score: 9, publishedIndex: 8)
    ].forEach { buffer.insert($0) }

    #expect(buffer.items.map(\.id) == ["high-new", "high-old", "mid"])
}

@Test func topCandidateBufferKeepsNewestCandidates() {
    var buffer = TopCandidateBuffer<Candidate>(
        limit: 2,
        areInPreferredOrder: { lhs, rhs in
            lhs.publishedIndex > rhs.publishedIndex
        }
    )

    [
        Candidate(id: "old", score: 100, publishedIndex: 1),
        Candidate(id: "newest", score: 0, publishedIndex: 5),
        Candidate(id: "middle", score: 10, publishedIndex: 3)
    ].forEach { buffer.insert($0) }

    #expect(buffer.items.map(\.id) == ["newest", "middle"])
}
