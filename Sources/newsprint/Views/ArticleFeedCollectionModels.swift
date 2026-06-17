import AppKit
import Foundation
import newsprintCore

typealias ArticleFeedDisplayItem = ArticleFeedSnapshot

struct ArticleFeedAppearance: Equatable {
    let theme: NewsprintTheme
    let readerFontChoice: ReaderFontChoice
    let readerFontSize: Int
    let density: ArticleListDensity

    var key: String {
        [
            theme.choice.rawValue,
            readerFontChoice.rawValue,
            "\(readerFontSize)",
            density.rawValue
        ].joined(separator: "|")
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

extension ArticleFeedDisplayItem {
    func heightCacheKey(width: CGFloat, appearance: ArticleFeedAppearance) -> ArticleFeedHeightCacheKey {
        ArticleFeedHeightCacheKey(
            articleID: id,
            isExpanded: true,
            width: Int(width.rounded()),
            themeRawValue: appearance.theme.choice.rawValue,
            readerFontRawValue: appearance.readerFontChoice.rawValue,
            readerFontSize: appearance.readerFontSize,
            densityRawValue: appearance.density.rawValue
        )
    }
}
