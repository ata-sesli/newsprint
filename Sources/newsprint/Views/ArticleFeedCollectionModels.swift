import AppKit
import Foundation
import newsprintCore

struct ArticleFeedDisplayItem: Identifiable {
    let article: Article
    let hackerNewsMetadata: HackerNewsMetadata?
    let metadataText: String
    let previewText: String?

    var id: String {
        article.id
    }

    init(article: Article) {
        self.article = article
        self.hackerNewsMetadata = HackerNewsMetadata(text: article.contentText ?? article.excerpt)
        self.metadataText = Self.metadataText(for: article)
        if self.hackerNewsMetadata == nil {
            self.previewText = HTMLTextExtractor.text(fromHTML: article.contentText ?? article.excerpt)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        } else {
            self.previewText = nil
        }
    }

    private static func metadataText(for article: Article) -> String {
        var parts = [article.sourceTitle]
        if let author = article.author, !author.isEmpty {
            parts.append(author)
        }
        parts.append((article.publishedAt ?? article.fetchedAt).formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct ArticleFeedItemModel: Identifiable {
    let displayItem: ArticleFeedDisplayItem
    let isExpanded: Bool
    let theme: NewsprintTheme
    let readerFontChoice: ReaderFontChoice
    let readerFontSize: Int
    let density: ArticleListDensity

    var article: Article {
        displayItem.article
    }

    var hackerNewsMetadata: HackerNewsMetadata? {
        displayItem.hackerNewsMetadata
    }

    var metadataText: String {
        displayItem.metadataText
    }

    var previewText: String? {
        displayItem.previewText
    }

    var id: String {
        article.id
    }
}

struct ArticleFeedHeightCacheKey: Hashable {
    let articleID: String
    let isExpanded: Bool
    let width: Int
    let themeRawValue: String
    let readerFontRawValue: String
    let readerFontSize: Int
    let densityRawValue: String
}

final class ArticleFeedHeightCache {
    private var values: [ArticleFeedHeightCacheKey: CGFloat] = [:]

    func height(for key: ArticleFeedHeightCacheKey) -> CGFloat? {
        values[key]
    }

    func setHeight(_ height: CGFloat, for key: ArticleFeedHeightCacheKey) {
        values[key] = height
    }

    func removeAll() {
        values.removeAll()
    }

    func removeHeights(articleID: String) {
        values = values.filter { $0.key.articleID != articleID }
    }
}

extension ArticleFeedItemModel {
    func heightCacheKey(width: CGFloat) -> ArticleFeedHeightCacheKey {
        ArticleFeedHeightCacheKey(
            articleID: id,
            isExpanded: isExpanded,
            width: Int(width.rounded()),
            themeRawValue: theme.choice.rawValue,
            readerFontRawValue: readerFontChoice.rawValue,
            readerFontSize: readerFontSize,
            densityRawValue: density.rawValue
        )
    }
}
