import Foundation
import Testing
@testable import newsprintCore

@Test func hackerNewsPageParserExtractsShowNewItemsInPageOrder() throws {
    let page = try HackerNewsPageClient.parseShowNewPage(html: showNewHTML(ids: [101, 102], nextPage: 2))

    #expect(page.items.map(\.id) == [101, 102])
    #expect(page.items.map(\.rank) == [1, 2])
    #expect(page.items.map(\.title) == ["Show HN: First", "Show HN: Second"])
    #expect(page.items.map(\.url?.absoluteString) == ["https://example.com/101", "https://example.com/102"])
    #expect(page.items.map(\.author) == ["tester101", "tester102"])
    #expect(page.items.map(\.points) == [12, 13])
    #expect(page.items.map(\.commentCount) == [2, 3])
    #expect(page.items.map(\.commentsURL.absoluteString) == [
        "https://news.ycombinator.com/item?id=101",
        "https://news.ycombinator.com/item?id=102"
    ])
    #expect(page.items.first?.postedAt == Date(timeIntervalSince1970: 1_782_406_901))
    #expect(page.nextPage == 2)
}

@Test func hackerNewsPageParserStopsWhenNoMoreLinkExists() throws {
    let page = try HackerNewsPageClient.parseShowNewPage(html: showNewHTML(ids: [201], nextPage: nil))

    #expect(page.items.map(\.id) == [201])
    #expect(page.nextPage == nil)
}

@Test func hackerNewsPageParserUsesThreadURLForSelfPosts() throws {
    let page = try HackerNewsPageClient.parseShowNewPage(html: showNewHTML(ids: [301], selfPostIDs: [301], nextPage: nil))

    #expect(page.items.first?.url?.absoluteString == "https://news.ycombinator.com/item?id=301")
}

func showNewHTML(ids: [Int], selfPostIDs: Set<Int> = [], nextPage: Int?) -> String {
    let rows = ids.enumerated().map { index, id in
        let href = selfPostIDs.contains(id) ? "item?id=\(id)" : "https://example.com/\(id)"
        return """
        <tr class="athing submission" id="\(id)">
          <td align="right" class="title"><span class="rank">\(index + 1).</span></td>
          <td class="votelinks"></td>
          <td class="title"><span class="titleline"><a href="\(href)">Show HN: \(name(for: index))</a></span></td>
        </tr>
        <tr><td colspan="2"></td><td class="subtext"><span class="subline"><span class="score" id="score_\(id)">\(12 + index) points</span> by <a href="user?id=tester\(id)" class="hnuser">tester\(id)</a> <span class="age" title="2026-06-25T17:01:41 178240690\(index + 1)"><a href="item?id=\(id)">14 minutes ago</a></span> | <a href="hide?id=\(id)&goto=shownew">hide</a> | <a href="item?id=\(id)">\(2 + index) comments</a></span></td></tr>
        """
    }.joined(separator: "\n")

    let more = nextPage.map { #"<tr class="morespace"></tr><tr><td colspan="2"></td><td class="title"><a href="shownew?p=\#($0)" class="morelink" rel="next">More</a></td></tr>"# } ?? ""
    return "<html><body><table>\(rows)\(more)</table></body></html>"
}

private func name(for index: Int) -> String {
    switch index {
    case 0: "First"
    case 1: "Second"
    case 2: "Third"
    default: "Item \(index + 1)"
    }
}
