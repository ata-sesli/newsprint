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

@Test func readerPolicyPreservesStructuredLocalContentHTML() throws {
    let body = String(repeating: "<p>Local paragraph with enough article text to qualify.</p>", count: 16)
    let article = Article(
        id: "structured-blog",
        sourceID: UUID(),
        sourceTitle: "Engineering Blog",
        title: "Structured Feed",
        url: URL(string: "https://example.com/structured")!,
        contentHTML: """
        <article>
          <script>track()</script>
          <h2>Section Heading</h2>
          \(body)
          <ul><li>First item</li><li>Second item</li></ul>
          <blockquote>Quoted idea</blockquote>
          <pre><code>let value = 1</code></pre>
        </article>
        """
    )

    let readable = try #require(ArticleReaderContentPolicy.localReadableArticle(for: article))

    #expect(readable.html.contains("<h2>Section Heading</h2>"))
    #expect(readable.html.contains("<ul><li>First item</li><li>Second item</li></ul>"))
    #expect(readable.html.contains("<blockquote>Quoted idea</blockquote>"))
    #expect(readable.html.contains("<pre><code>let value = 1</code></pre>"))
    #expect(!readable.html.contains("<script"))
}

@Test func readerPolicyConvertsPlainLocalTextIntoParagraphs() throws {
    let first = String(repeating: "First paragraph sentence. ", count: 18)
    let second = String(repeating: "Second paragraph sentence. ", count: 18)
    let article = Article(
        id: "plain-blog",
        sourceID: UUID(),
        sourceTitle: "Plain Blog",
        title: "Plain Feed",
        url: URL(string: "https://example.com/plain")!,
        contentText: "\(first)\n\n\(second)"
    )

    let readable = try #require(ArticleReaderContentPolicy.localReadableArticle(for: article))

    #expect(readable.html.contains("</p>\n<p>"))
    #expect(readable.html.contains("First paragraph sentence."))
    #expect(readable.html.contains("Second paragraph sentence."))
}

@Test func readerHTMLSanitizerRemovesUnsafeTagsHandlersAndLinks() {
    let html = """
    <article>
      <p onclick="steal()">Safe text <a href="javascript:alert(1)" onmouseover="track()">bad link</a></p>
      <iframe src="https://tracker.example"></iframe>
      <form><input name="email"></form>
      <style>body { display:none }</style>
    </article>
    """

    let sanitized = ArticleReaderHTMLSanitizer.sanitize(html, baseURL: URL(string: "https://example.com/post")!)

    #expect(sanitized.contains("<p>Safe text <a>bad link</a></p>"))
    #expect(!sanitized.contains("onclick"))
    #expect(!sanitized.contains("javascript:"))
    #expect(!sanitized.contains("<iframe"))
    #expect(!sanitized.contains("<form"))
    #expect(!sanitized.contains("<style"))
}

@Test func readerHTMLSanitizerPreservesSafeImagesAndRemovesUnsafeImageSources() {
    let html = """
    <article>
      <p>Before image.</p>
      <img src="/images/chart.png" alt="Latency chart" onclick="track()">
      <img src="javascript:alert(1)" alt="Bad image">
      <p>After image.</p>
    </article>
    """

    let sanitized = ArticleReaderHTMLSanitizer.sanitize(html, baseURL: URL(string: "https://example.com/post")!)

    #expect(sanitized.contains("<img src=\"https://example.com/images/chart.png\" alt=\"Latency chart\">"))
    #expect(!sanitized.contains("javascript:"))
    #expect(!sanitized.contains("onclick"))
    #expect(sanitized.contains("<p>Before image.</p>"))
    #expect(sanitized.contains("<p>After image.</p>"))
}

@Test func readerHTMLSanitizerPreservesPreformattedCodeNewlines() {
    let html = """
    <article>
      <pre><code>let first = 1
    let second = 2
    print(first + second)</code></pre>
    </article>
    """

    let sanitized = ArticleReaderHTMLSanitizer.sanitize(html, baseURL: URL(string: "https://example.com/post")!)

    #expect(sanitized.contains("let first = 1\nlet second = 2\nprint(first + second)"))
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
