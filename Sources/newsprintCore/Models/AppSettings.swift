import Foundation
import SwiftData

@Model
public final class AppSettings {
    public var retentionDays: Int
    public var refreshOnLaunch: Bool
    public var refreshOnManualCommand: Bool
    public var refreshWhileOpenMinutes: Int?
    public var openLinksInDefaultBrowser: Bool
    public var markReadOnOpen: Bool
    public var lastRetentionCleanupAt: Date?
    public var lastRetentionDeletedCount: Int
    public var themeRawValue: String
    public var readerFontRawValue: String
    public var readerFontSize: Int
    public var articleListDensityRawValue: String

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
        refreshOnManualCommand: Bool = true,
        refreshWhileOpenMinutes: Int? = nil,
        openLinksInDefaultBrowser: Bool = true,
        markReadOnOpen: Bool = false,
        lastRetentionCleanupAt: Date? = nil,
        lastRetentionDeletedCount: Int = 0,
        theme: AppThemeChoice = .system,
        readerFont: ReaderFontChoice = .system,
        readerFontSize: Int = 17,
        articleListDensity: ArticleListDensity = .comfortable
    ) {
        self.retentionDays = retentionDays
        self.refreshOnLaunch = refreshOnLaunch
        self.refreshOnManualCommand = refreshOnManualCommand
        self.refreshWhileOpenMinutes = refreshWhileOpenMinutes
        self.openLinksInDefaultBrowser = openLinksInDefaultBrowser
        self.markReadOnOpen = markReadOnOpen
        self.lastRetentionCleanupAt = lastRetentionCleanupAt
        self.lastRetentionDeletedCount = lastRetentionDeletedCount
        self.themeRawValue = theme.rawValue
        self.readerFontRawValue = readerFont.rawValue
        self.readerFontSize = min(max(readerFontSize, Self.readerFontSizeRange.lowerBound), Self.readerFontSizeRange.upperBound)
        self.articleListDensityRawValue = articleListDensity.rawValue
    }

    public static var readerFontSizeRange: ClosedRange<Int> {
        13...26
    }

    public func clampReaderFontSize(_ value: Int) {
        readerFontSize = min(max(value, Self.readerFontSizeRange.lowerBound), Self.readerFontSizeRange.upperBound)
    }
}
