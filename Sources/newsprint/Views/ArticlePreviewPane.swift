import AppKit
import SwiftUI
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
        guard let text = (article.contentText ?? article.excerpt)?.nilIfBlank else {
            return nil
        }
        return ReadableArticle(
            title: article.title,
            byline: article.author,
            siteName: article.sourceTitle,
            url: url,
            html: "<p>\(text)</p>",
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

            Button("Hide Preview", systemImage: "sidebar.right") {
                isCollapsed = true
            }
            .buttonStyle(.borderless)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    if let siteName = article.siteName {
                        Text(siteName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.metadata)
                    }

                    Text(article.title)
                        .font(.system(size: CGFloat(readerFontSize) * 1.55, weight: .semibold, design: readerFontChoice.fontDesign))
                        .lineSpacing(4)

                    if let byline = article.byline {
                        Text(byline)
                            .font(.callout)
                            .foregroundStyle(theme.metadata)
                    }
                }

                Divider()

                Text(article.text)
                    .font(.system(size: CGFloat(readerFontSize), design: readerFontChoice.fontDesign))
                    .lineSpacing(7)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.readerBackground)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
