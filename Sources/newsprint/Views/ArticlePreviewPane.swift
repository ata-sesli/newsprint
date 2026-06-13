import AppKit
import SwiftUI
import WebKit
import newsprintCore

@MainActor
final class ArticlePreviewViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading(URL)
        case loaded(ReadableArticle)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var currentArticleID: String?
    private let fetcher = ReadableArticleFetcher()
    private let extractor = ReadableArticleExtractor()

    func load(article: Article?) async {
        guard let article, let url = ArticlePreviewTarget.url(for: article) else {
            currentArticleID = nil
            state = .idle
            return
        }

        guard currentArticleID != article.id else {
            return
        }

        currentArticleID = article.id
        state = .loading(url)

        do {
            if let localReadable = ArticleReaderContentPolicy.localReadableArticle(for: article) {
                state = .loaded(localReadable)
                return
            }

            if let readmeURL = ArticleReaderContentPolicy.githubReadmeURL(for: url) {
                let markdown = try await fetcher.fetch(url: readmeURL)
                guard currentArticleID == article.id else { return }
                state = .loaded(readmeArticle(from: article, readmeURL: readmeURL, markdown: markdown))
                return
            }

            let html = try await fetcher.fetch(url: url)
            let readable = try extractor.extract(html: html, url: url)
            guard currentArticleID == article.id else { return }
            state = .loaded(readable)
        } catch {
            guard currentArticleID == article.id else { return }
            if let fallback = fallbackArticle(from: article, url: url) {
                state = .loaded(fallback)
            } else {
                state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func reset() {
        currentArticleID = nil
        state = .idle
    }

    private func fallbackArticle(from article: Article, url: URL) -> ReadableArticle? {
        guard let text = HTMLTextExtractor.text(fromHTML: article.contentText ?? article.excerpt), text.nilIfBlank != nil else {
            return nil
        }
        return ReadableArticle(
            title: article.title,
            byline: article.author,
            siteName: article.sourceTitle,
            url: url,
            html: ArticleReaderHTMLSanitizer.paragraphHTML(fromPlainText: text),
            text: text
        )
    }

    private func readmeArticle(from article: Article, readmeURL: URL, markdown: String) -> ReadableArticle {
        let text = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReadableArticle(
            title: "\(article.title) README",
            byline: article.author,
            siteName: article.sourceTitle,
            url: readmeURL,
            html: ArticleReaderHTMLSanitizer.preformattedHTML(fromPlainText: text),
            text: text
        )
    }
}

struct ArticlePreviewPane: View {
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    let article: Article?
    @Binding var previewMode: PreviewMode
    @Binding var isCollapsed: Bool
    @StateObject private var viewModel = ArticlePreviewViewModel()

    private var previewURL: URL? {
        article.flatMap(ArticlePreviewTarget.url(for:))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .background(theme.readerBackground)
        .task(id: article?.id) {
            if previewMode == .reader {
                await viewModel.load(article: article)
            }
        }
        .onChange(of: previewMode) {
            if previewMode == .reader {
                Task { await viewModel.load(article: article) }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Preview Mode", selection: $previewMode) {
                Text("Reader").tag(PreviewMode.reader)
                Text("Web").tag(PreviewMode.web)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)

            Spacer()

            if let previewURL {
                Button("Open Original", systemImage: "safari") {
                    NSWorkspace.shared.open(previewURL)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.paneBackground)
    }

    @ViewBuilder
    private var content: some View {
        if article == nil {
            ContentUnavailableView("No Preview", systemImage: "doc.text.magnifyingglass", description: Text("Select an article to preview it here."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if previewMode == .web {
            ArticleWebPreviewView(url: previewURL)
        } else {
            readerContent
        }
    }

    @ViewBuilder
    private var readerContent: some View {
        switch viewModel.state {
        case .idle:
            ContentUnavailableView("No Preview", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ProgressView("Loading reader view...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let readable):
            ReaderPreviewView(article: readable)
        case .failed(let message):
            VStack(spacing: 14) {
                ContentUnavailableView("Reader Unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
                if previewURL != nil {
                    Button("Use Web Mode", systemImage: "globe") {
                        previewMode = .web
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ReaderPreviewView: View {
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    let article: ReadableArticle

    var body: some View {
        ReaderHTMLPreviewView(
            article: article,
            theme: theme,
            readerFontChoice: readerFontChoice,
            readerFontSize: readerFontSize
        )
    }
}

struct ReaderHTMLPreviewView: NSViewRepresentable {
    let article: ReadableArticle
    let theme: NewsprintTheme
    let readerFontChoice: ReaderFontChoice
    let readerFontSize: Int

    func makeCoordinator() -> ReaderHTMLNavigationDelegate {
        ReaderHTMLNavigationDelegate()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let document = ReaderHTMLDocumentBuilder.document(
            article: article,
            theme: theme,
            readerFontChoice: readerFontChoice,
            readerFontSize: readerFontSize
        )
        webView.loadHTMLString(document, baseURL: article.url)
    }
}

enum ReaderHTMLDocumentBuilder {
    static func document(
        article: ReadableArticle,
        theme: NewsprintTheme,
        readerFontChoice: ReaderFontChoice,
        readerFontSize: Int
    ) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            \(css(theme: theme, readerFontChoice: readerFontChoice, readerFontSize: readerFontSize))
          </style>
        </head>
        <body>
          <main>
            <header>
              \(article.siteName.map { "<div class=\"site\">\(escapeHTML($0))</div>" } ?? "")
              <h1>\(escapeHTML(article.title))</h1>
              \(article.byline.map { "<div class=\"byline\">\(escapeHTML($0))</div>" } ?? "")
            </header>
            <hr>
            <article class="content">
              \(article.html)
            </article>
          </main>
        </body>
        </html>
        """
    }

    private static func css(theme: NewsprintTheme, readerFontChoice: ReaderFontChoice, readerFontSize: Int) -> String {
        let bodyFont = fontFamily(for: readerFontChoice)
        let monoFont = #"ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace"#
        return """
        :root {
          color-scheme: light dark;
          --background: \(cssColor(theme.readerBackground, fallback: .textBackgroundColor));
          --surface: \(cssColor(theme.readerSurface, fallback: .controlBackgroundColor));
          --text: \(cssColor(Color.primary, fallback: .labelColor));
          --metadata: \(cssColor(theme.metadata, fallback: .secondaryLabelColor));
          --accent: \(cssColor(theme.rowAccent, fallback: .controlAccentColor));
          --separator: \(cssColor(Color(nsColor: .separatorColor), fallback: .separatorColor));
        }
        html, body {
          margin: 0;
          padding: 0;
          background: var(--background);
          color: var(--text);
          font-family: \(bodyFont);
          font-size: \(readerFontSize)px;
          line-height: 1.68;
        }
        body {
          padding: 28px 34px 42px;
          box-sizing: border-box;
        }
        main {
          max-width: 760px;
          margin: 0 auto;
        }
        header {
          margin-bottom: 18px;
        }
        .site, .byline {
          color: var(--metadata);
          font-size: 0.88rem;
          font-weight: 650;
          margin-bottom: 0.45rem;
        }
        h1 {
          font-size: 1.55rem;
          line-height: 1.18;
          margin: 0.2rem 0 0.7rem;
        }
        h2, h3, h4 {
          line-height: 1.25;
          margin: 1.55rem 0 0.65rem;
        }
        p {
          margin: 0 0 1.1rem;
        }
        ul, ol {
          margin: 0 0 1.15rem 1.35rem;
          padding: 0;
        }
        li {
          margin: 0.35rem 0;
        }
        blockquote {
          margin: 1.2rem 0;
          padding: 0.2rem 0 0.2rem 1rem;
          border-left: 4px solid var(--accent);
          color: var(--metadata);
        }
        pre {
          overflow-x: auto;
          white-space: pre;
          background: var(--surface);
          border: 1px solid var(--separator);
          border-radius: 8px;
          padding: 0.85rem 0.95rem;
          margin: 1.2rem 0;
          line-height: 1.45;
        }
        code {
          font-family: \(monoFont);
          font-size: 0.82em;
        }
        pre code {
          white-space: pre;
          font-size: 0.82rem;
          line-height: 1.45;
        }
        img {
          display: block;
          max-width: 100%;
          height: auto;
          margin: 1.25rem auto;
          border-radius: 8px;
        }
        a {
          color: var(--accent);
          text-decoration-thickness: 0.08em;
          text-underline-offset: 0.18em;
        }
        hr {
          border: 0;
          border-top: 1px solid var(--separator);
          margin: 0 0 1.4rem;
        }
        """
    }

    private static func fontFamily(for choice: ReaderFontChoice) -> String {
        switch choice {
        case .system:
            #"-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif"#
        case .serif:
            #"ui-serif, Georgia, "Times New Roman", serif"#
        case .rounded:
            #""SF Pro Rounded", -apple-system, BlinkMacSystemFont, sans-serif"#
        case .monospaced:
            #"ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace"#
        }
    }

    private static func cssColor(_ color: Color, fallback: NSColor) -> String {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? fallback.usingColorSpace(.sRGB) ?? fallback
        return String(
            format: "rgba(%d, %d, %d, %.3f)",
            Int(round(resolved.redComponent * 255)),
            Int(round(resolved.greenComponent * 255)),
            Int(round(resolved.blueComponent * 255)),
            Double(resolved.alphaComponent)
        )
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

final class ReaderHTMLNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
