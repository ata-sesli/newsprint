import AppKit
import Foundation
import newsprintCore

struct ArticleFeedItemModel: Identifiable {
    let article: Article
    let isExpanded: Bool
    let hackerNewsMetadata: HackerNewsMetadata?
    let metadataText: String
    let theme: NewsprintTheme
    let readerFontChoice: ReaderFontChoice
    let readerFontSize: Int
    let density: ArticleListDensity

    var id: String {
        article.id
    }

    static func metadataText(for article: Article) -> String {
        var parts = [article.sourceTitle]
        if let author = article.author, !author.isEmpty {
            parts.append(author)
        }
        parts.append((article.publishedAt ?? article.fetchedAt).formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
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
