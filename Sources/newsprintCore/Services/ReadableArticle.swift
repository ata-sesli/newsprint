import Foundation

public struct ReadableArticle: Equatable, Sendable {
    public let title: String
    public let byline: String?
    public let siteName: String?
    public let url: URL
    public let html: String
    public let text: String

    public init(title: String, byline: String?, siteName: String?, url: URL, html: String, text: String) {
        self.title = title
        self.byline = byline
        self.siteName = siteName
        self.url = url
        self.html = html
        self.text = text
    }
}

public enum ReadableArticleExtractionError: LocalizedError, Equatable {
    case emptyDocument
    case noReadableContent

    public var errorDescription: String? {
        switch self {
        case .emptyDocument:
            "The page did not contain any HTML."
        case .noReadableContent:
            "Newsprint could not find a readable article on this page."
        }
    }
}

public struct ReadableArticleFetcher: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Newsprint/1.0 (+https://local.newsprint)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

public struct ReadableArticleExtractor: Sendable {
    public init() {}

    public func extract(html: String, url: URL) throws -> ReadableArticle {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ReadableArticleExtractionError.emptyDocument
        }

        let cleaned = removeUnwantedBlocks(from: trimmed)
        guard let selected = bestCandidate(in: cleaned),
              let text = HTMLTextExtractor.text(fromHTML: Optional(selected)),
              text.count >= 20 else {
            throw ReadableArticleExtractionError.noReadableContent
        }

        let title = firstMatch(#"(?is)<h1\b[^>]*>(.*?)</h1>"#, in: selected)
            .flatMap { HTMLTextExtractor.text(fromHTML: Optional($0)) }
            ?? firstMetaContent(named: "og:title", in: cleaned)
            ?? firstMatch(#"(?is)<title\b[^>]*>(.*?)</title>"#, in: cleaned).flatMap { HTMLTextExtractor.text(fromHTML: Optional($0)) }
            ?? url.host() ?? url.absoluteString

        let byline = firstMetaContent(named: "author", in: cleaned)
        let siteName = firstMetaContent(named: "og:site_name", in: cleaned) ?? url.host()
        let sanitized = ArticleReaderHTMLSanitizer.sanitize(selected, baseURL: url)

        return ReadableArticle(
            title: title,
            byline: byline,
            siteName: siteName,
            url: url,
            html: sanitized,
            text: HTMLTextExtractor.text(fromHTML: Optional(sanitized)) ?? text
        )
    }

    private func removeUnwantedBlocks(from html: String) -> String {
        var output = html
        for pattern in [
            #"(?is)<(script|style|noscript|svg|iframe|form|nav|footer|header|aside)\b[^>]*>.*?</\1>"#,
            #"(?is)<([a-z0-9]+)\b[^>]*(?:class|id)=["'][^"']*(?:ad-|ads|advert|promo|subscribe|newsletter|cookie|related|sidebar)[^"']*["'][^>]*>.*?</\1>"#
        ] {
            output = output.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return output
    }

    private func bestCandidate(in html: String) -> String? {
        let candidates = [
            candidates(matching: #"(?is)<article\b[^>]*>(.*?)</article>"#, in: html),
            candidates(matching: #"(?is)<main\b[^>]*>(.*?)</main>"#, in: html),
            candidates(matching: #"(?is)<(?:div|section)\b[^>]*(?:class|id)=["'][^"']*(?:article|content|post|entry)[^"']*["'][^>]*>(.*?)</(?:div|section)>"#, in: html)
        ].flatMap { $0 }

        return candidates.max { lhs, rhs in
            (HTMLTextExtractor.text(fromHTML: Optional(lhs))?.count ?? 0) < (HTMLTextExtractor.text(fromHTML: Optional(rhs))?.count ?? 0)
        }
    }

    private func candidates(matching pattern: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let bodyRange = Range(match.range(at: 1), in: html) else {
                return nil
            }
            return String(html[bodyRange])
        }
    }

    private func sanitize(_ html: String, baseURL: URL) -> String {
        let allowed: Set<String> = ["p", "h1", "h2", "h3", "h4", "ul", "ol", "li", "blockquote", "pre", "code", "strong", "b", "em", "i", "a", "br"]
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<\s*(/?)\s*([a-z0-9]+)([^>]*)>"#) else {
            return html
        }

        var result = ""
        var cursor = html.startIndex
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let fullRange = Range(match.range(at: 0), in: html),
                  let slashRange = Range(match.range(at: 1), in: html),
                  let tagRange = Range(match.range(at: 2), in: html),
                  let attrRange = Range(match.range(at: 3), in: html) else {
                continue
            }

            result += html[cursor..<fullRange.lowerBound]
            let tag = html[tagRange].lowercased()
            let isClosing = !html[slashRange].isEmpty
            if allowed.contains(String(tag)) {
                result += replacementTag(tag: String(tag), attributes: String(html[attrRange]), isClosing: isClosing, baseURL: baseURL)
            }
            cursor = fullRange.upperBound
        }
        result += html[cursor..<html.endIndex]
        return result
            .replacingOccurrences(of: #"(?is)<!--.*?-->"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacementTag(tag: String, attributes: String, isClosing: Bool, baseURL: URL) -> String {
        if isClosing {
            return tag == "br" ? "" : "</\(tag)>"
        }
        if tag == "br" {
            return "<br>"
        }
        if tag == "a", let href = firstAttribute("href", in: attributes), let absoluteURL = URL(string: href, relativeTo: baseURL)?.absoluteURL {
            return "<a href=\"\(escapeAttribute(absoluteURL.absoluteString))\">"
        }
        return "<\(tag)>"
    }

    private func firstAttribute(_ name: String, in text: String) -> String? {
        firstMatch(#"(?i)\b\#(name)\s*=\s*["']([^"']+)["']"#, in: text, rangeIndex: 1)
    }

    private func firstMetaContent(named name: String, in html: String) -> String? {
        firstMatch(#"(?is)<meta\b[^>]*(?:name|property)=["']\#(NSRegularExpression.escapedPattern(for: name))["'][^>]*content=["']([^"']+)["'][^>]*>"#, in: html, rangeIndex: 1)
            ?? firstMatch(#"(?is)<meta\b[^>]*content=["']([^"']+)["'][^>]*(?:name|property)=["']\#(NSRegularExpression.escapedPattern(for: name))["'][^>]*>"#, in: html, rangeIndex: 1)
    }

    private func firstMatch(_ pattern: String, in text: String, rangeIndex: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > rangeIndex,
              let matchRange = Range(match.range(at: rangeIndex), in: text) else {
            return nil
        }
        return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

public enum PreviewMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case reader
    case web

    public var id: String { rawValue }

    public init(storedRawValue: String) {
        self = PreviewMode(rawValue: storedRawValue) ?? .reader
    }
}

public enum ArticlePreviewTarget {
    public static func url(for article: Article) -> URL? {
        HackerNewsMetadata(text: article.contentText ?? article.excerpt)?.articleURL ?? article.url
    }
}

public enum ArticleReaderContentPolicy {
    public static func localReadableArticle(for article: Article, minimumTextLength: Int = 500) -> ReadableArticle? {
        guard HackerNewsMetadata(text: article.contentText ?? article.excerpt) == nil else {
            return nil
        }

        if let contentHTML = article.contentHTML {
            let sanitized = ArticleReaderHTMLSanitizer.sanitize(contentHTML, baseURL: ArticlePreviewTarget.url(for: article) ?? article.url)
            if let text = HTMLTextExtractor.text(fromHTML: Optional(sanitized)), text.count >= minimumTextLength {
                return ReadableArticle(
                    title: article.title,
                    byline: article.author,
                    siteName: article.sourceTitle,
                    url: ArticlePreviewTarget.url(for: article) ?? article.url,
                    html: sanitized,
                    text: text
                )
            }
        }

        guard let rawText = article.contentText ?? article.excerpt,
              let text = HTMLTextExtractor.textPreservingParagraphBreaks(fromHTML: rawText),
              text.count >= minimumTextLength else {
                return nil
        }

        return ReadableArticle(
            title: article.title,
            byline: article.author,
            siteName: article.sourceTitle,
            url: ArticlePreviewTarget.url(for: article) ?? article.url,
            html: ArticleReaderHTMLSanitizer.paragraphHTML(fromPlainText: text),
            text: text
        )
    }

    public static func githubReadmeURL(for url: URL) -> URL? {
        guard url.host()?.lowercased() == "github.com" else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2,
              !components[0].isEmpty,
              !components[1].isEmpty else {
            return nil
        }

        return URL(string: "https://raw.githubusercontent.com/\(components[0])/\(components[1])/HEAD/README.md")
    }

}

public enum ArticleReaderHTMLSanitizer {
    private static let allowedTags: Set<String> = ["p", "h1", "h2", "h3", "h4", "ul", "ol", "li", "blockquote", "pre", "code", "strong", "b", "em", "i", "a", "br", "img"]

    public static func sanitize(_ html: String, baseURL: URL) -> String {
        let cleaned = removeUnwantedBlocks(from: html)
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<\s*(/?)\s*([a-z0-9]+)([^>]*)>"#) else {
            return cleaned
        }

        var result = ""
        var cursor = cleaned.startIndex
        let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        for match in regex.matches(in: cleaned, range: range) {
            guard let fullRange = Range(match.range(at: 0), in: cleaned),
                  let slashRange = Range(match.range(at: 1), in: cleaned),
                  let tagRange = Range(match.range(at: 2), in: cleaned),
                  let attrRange = Range(match.range(at: 3), in: cleaned) else {
                continue
            }

            result += cleaned[cursor..<fullRange.lowerBound]
            let tag = cleaned[tagRange].lowercased()
            let isClosing = !cleaned[slashRange].isEmpty
            if allowedTags.contains(String(tag)) {
                result += replacementTag(tag: String(tag), attributes: String(cleaned[attrRange]), isClosing: isClosing, baseURL: baseURL)
            }
            cursor = fullRange.upperBound
        }
        result += cleaned[cursor..<cleaned.endIndex]

        return result
            .replacingOccurrences(of: #"(?is)<!--.*?-->"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #">\s+<"#, with: "><", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func paragraphHTML(fromPlainText text: String) -> String {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return paragraphs
            .map { "<p>\(escapeHTML($0))</p>" }
            .joined(separator: "\n")
    }

    public static func preformattedHTML(fromPlainText text: String) -> String {
        "<pre><code>\(escapeHTML(text))</code></pre>"
    }

    private static func removeUnwantedBlocks(from html: String) -> String {
        var output = html
        for pattern in [
            #"(?is)<(script|style|noscript|svg|iframe|form|nav|footer|header|aside)\b[^>]*>.*?</\1>"#,
            #"(?is)<([a-z0-9]+)\b[^>]*(?:class|id)=["'][^"']*(?:ad-|ads|advert|promo|subscribe|newsletter|cookie|related|sidebar)[^"']*["'][^>]*>.*?</\1>"#
        ] {
            output = output.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return output
    }

    private static func replacementTag(tag: String, attributes: String, isClosing: Bool, baseURL: URL) -> String {
        if isClosing {
            return tag == "br" ? "" : "</\(tag)>"
        }
        if tag == "br" {
            return "<br>"
        }
        if tag == "img", let src = firstAttribute("src", in: attributes), let absoluteURL = URL(string: src, relativeTo: baseURL)?.absoluteURL, isAllowedImage(absoluteURL) {
            let alt = firstAttribute("alt", in: attributes).map { " alt=\"\(escapeHTML($0))\"" } ?? ""
            return "<img src=\"\(escapeHTML(absoluteURL.absoluteString))\"\(alt)>"
        }
        if tag == "img" {
            return ""
        }
        if tag == "a", let href = firstAttribute("href", in: attributes), let absoluteURL = URL(string: href, relativeTo: baseURL)?.absoluteURL, isAllowedLink(absoluteURL) {
            return "<a href=\"\(escapeHTML(absoluteURL.absoluteString))\">"
        }
        if tag == "a" {
            return "<a>"
        }
        return "<\(tag)>"
    }

    private static func firstAttribute(_ name: String, in text: String) -> String? {
        firstMatch(#"(?i)\b\#(name)\s*=\s*["']([^"']+)["']"#, in: text)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isAllowedLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return ["http", "https", "mailto"].contains(scheme)
    }

    private static func isAllowedImage(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return ["http", "https"].contains(scheme)
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

public enum WebContentBlockerRules {
    public static let identifier = "NewsprintCuratedContentBlocker"

    public static let json = """
    [
      {
        "trigger": { "url-filter": ".*", "if-domain": ["doubleclick.net", "googlesyndication.com", "google-analytics.com", "googletagmanager.com", "facebook.net", "scorecardresearch.com"] },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": ".*", "resource-type": ["image", "style-sheet"], "url-filter-is-case-sensitive": false, "if-top-url": [".*"] },
        "action": { "type": "css-display-none", "selector": ".ad, .ads, .advertisement, [class*='ad-'], [id*='ad-'], [class*='sponsor'], [id*='sponsor']" }
      }
    ]
    """
}
