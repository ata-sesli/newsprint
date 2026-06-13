import Foundation
import SwiftData

@Model
public final class AppSettings {
    public var retentionDays: Int
    public var refreshOnLaunch: Bool
    public var refreshWhileOpenMinutes: Int?
    public var markReadOnOpen: Bool
    public var lastRetentionCleanupAt: Date?
    public var lastRetentionDeletedCount: Int
    public var themeRawValue: String
    public var readerFontRawValue: String
    public var readerFontSize: Int
    public var articleListDensityRawValue: String
    public var webPreviewHorizontalPadding: Int = 8

    public var themeChoice: AppThemeChoice {
        get { AppThemeChoice(rawValue: themeRawValue) ?? .system }
        set { themeRawValue = newValue.rawValue }
    }

    public var readerFontChoice: ReaderFontChoice {
        get { ReaderFontChoice(rawValue: readerFontRawValue) ?? .system }
        set { readerFontRawValue = newValue.rawValue }
    }

    public var articleListDensity: ArticleListDensity {
        get { ArticleListDensity(rawValue: articleListDensityRawValue) ?? .comfortable }
        set { articleListDensityRawValue = newValue.rawValue }
    }

    public init(
        retentionDays: Int = 7,
        refreshOnLaunch: Bool = true,
        refreshWhileOpenMinutes: Int? = nil,
        markReadOnOpen: Bool = false,
        lastRetentionCleanupAt: Date? = nil,
        lastRetentionDeletedCount: Int = 0,
        theme: AppThemeChoice = .system,
        readerFont: ReaderFontChoice = .system,
        readerFontSize: Int = 17,
        articleListDensity: ArticleListDensity = .comfortable,
        webPreviewHorizontalPadding: Int = 8
    ) {
        self.retentionDays = retentionDays
        self.refreshOnLaunch = refreshOnLaunch
        self.refreshWhileOpenMinutes = refreshWhileOpenMinutes
        self.markReadOnOpen = markReadOnOpen
        self.lastRetentionCleanupAt = lastRetentionCleanupAt
        self.lastRetentionDeletedCount = lastRetentionDeletedCount
        self.themeRawValue = theme.rawValue
        self.readerFontRawValue = readerFont.rawValue
        self.readerFontSize = min(max(readerFontSize, Self.readerFontSizeRange.lowerBound), Self.readerFontSizeRange.upperBound)
        self.articleListDensityRawValue = articleListDensity.rawValue
        self.webPreviewHorizontalPadding = min(max(webPreviewHorizontalPadding, Self.webPreviewHorizontalPaddingRange.lowerBound), Self.webPreviewHorizontalPaddingRange.upperBound)
    }

    public static var readerFontSizeRange: ClosedRange<Int> {
        13...26
    }

    public func clampReaderFontSize(_ value: Int) {
        readerFontSize = min(max(value, Self.readerFontSizeRange.lowerBound), Self.readerFontSizeRange.upperBound)
    }

    public static var webPreviewHorizontalPaddingRange: ClosedRange<Int> {
        0...32
    }

    public func clampWebPreviewHorizontalPadding(_ value: Int) {
        webPreviewHorizontalPadding = min(max(value, Self.webPreviewHorizontalPaddingRange.lowerBound), Self.webPreviewHorizontalPaddingRange.upperBound)
    }
}
