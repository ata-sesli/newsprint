import Foundation
import Testing
@testable import newsprintCore

@Test func readableExtractorRemovesChromeScriptsAndAdBlocks() throws {
    let html = """
    <html>
      <head><title>Example Story</title><script>track()</script><style>.ad{}</style></head>
      <body>
        <nav>Navigation</nav>
        <article>
          <h1>Readable Title</h1>
          <p>First paragraph.</p>
          <div class="ad-banner">Buy now</div>
          <footer>Footer links</footer>
        </article>
      </body>
    </html>
    """

    let article = try ReadableArticleExtractor().extract(html: html, url: URL(string: "https://example.com/story")!)

    #expect(article.title == "Readable Title")
    #expect(article.text.contains("First paragraph."))
    #expect(!article.text.contains("Navigation"))
    #expect(!article.text.contains("Buy now"))
    #expect(!article.html.contains("<script"))
    #expect(!article.html.contains("ad-banner"))
}

@Test func readableExtractorChoosesMainArticleOverBoilerplate() throws {
    let html = """
    <html>
      <body>
        <section class="related"><p>Related link one</p><p>Related link two</p></section>
        <main>
          <h1>Main Article</h1>
          <p>This is the useful story body with enough words to win.</p>
          <p>It should be selected instead of related links.</p>
        </main>
      </body>
    </html>
    """

    let article = try ReadableArticleExtractor().extract(html: html, url: URL(string: "https://example.com/main")!)

    #expect(article.title == "Main Article")
    #expect(article.text.contains("useful story body"))
    #expect(!article.text.contains("Related link one"))
}

@Test func readableExtractorPreservesSafeArticleMarkup() throws {
    let html = """
    <article>
      <h1>Markup Story</h1>
      <p>A paragraph with <a href="/docs">a link</a> and <strong>bold</strong>.</p>
      <blockquote>quoted text</blockquote>
      <pre><code>let value = 1</code></pre>
    </article>
    """

    let article = try ReadableArticleExtractor().extract(html: html, url: URL(string: "https://example.com/posts/1")!)

    #expect(article.html.contains("<p>"))
    #expect(article.html.contains("<a href=\"https://example.com/docs\">"))
    #expect(article.html.contains("<blockquote>"))
    #expect(article.html.contains("<pre><code>"))
    #expect(article.text.contains("let value = 1"))
}

@Test func previewTargetUsesHackerNewsArticleURLBeforeFeedURL() {
    let article = Article(
        id: "hn",
        sourceID: UUID(),
        sourceTitle: "HN",
        title: "HN Item",
        url: URL(string: "https://news.ycombinator.com/item?id=1")!,
        contentText: "Article URL: https://example.com/story Comments URL: https://news.ycombinator.com/item?id=1 Points: 3 # Comments: 4"
    )

    #expect(ArticlePreviewTarget.url(for: article)?.absoluteString == "https://example.com/story")
}

@Test func readerPolicyPrefersLongLocalNonHackerNewsText() throws {
    let article = Article(
        id: "blog",
        sourceID: UUID(),
        sourceTitle: "GitHub Engineering",
        title: "Modernizing navigation",
        url: URL(string: "https://github.blog/example")!,
        author: "Alex",
        excerpt: "When you&rsquo;re working through a backlog&mdash;latency matters. " + String(repeating: "Local feed text. ", count: 30),
        contentText: nil
    )

    let readable = try #require(ArticleReaderContentPolicy.localReadableArticle(for: article))

    #expect(readable.title == "Modernizing navigation")
    #expect(readable.byline == "Alex")
    #expect(readable.siteName == "GitHub Engineering")
    #expect(readable.text.contains("When you're working through a backlog-latency matters."))
}

@Test func readerPolicyDoesNotPreferHackerNewsMetadataAsLocalArticle() {
    let article = Article(
        id: "hn-local",
        sourceID: UUID(),
        sourceTitle: "Hacker News",
        title: "HN",
        url: URL(string: "https://news.ycombinator.com/item?id=1")!,
        contentText: "Article URL: https://example.com/story Comments URL: https://news.ycombinator.com/item?id=1 Points: 3 # Comments: 4"
    )

    #expect(ArticleReaderContentPolicy.localReadableArticle(for: article) == nil)
}

@Test func readerPolicyBuildsGitHubReadmeURLForRepository() {
    let url = URL(string: "https://github.com/apple/swift")!

    #expect(ArticleReaderContentPolicy.githubReadmeURL(for: url)?.absoluteString == "https://raw.githubusercontent.com/apple/swift/HEAD/README.md")
}

@Test func previewModeFallsBackToReaderForInvalidRawValue() {
    #expect(PreviewMode(rawValue: "web") == .web)
    #expect(PreviewMode(storedRawValue: "bogus") == .reader)
}

@Test func webContentBlockerRulesAreValidJSONList() throws {
    let data = Data(WebContentBlockerRules.json.utf8)
    let object = try JSONSerialization.jsonObject(with: data)
    let rules = try #require(object as? [[String: Any]])

    #expect(!rules.isEmpty)
    #expect(rules.allSatisfy { $0["trigger"] != nil && $0["action"] != nil })
}
