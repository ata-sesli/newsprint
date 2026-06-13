import Testing
@testable import newsprintCore

@Test func appSettingsAppearanceDefaults() {
    let settings = AppSettings()

    #expect(settings.themeChoice == .system)
    #expect(settings.readerFontChoice == .system)
    #expect(settings.readerFontSize == 17)
    #expect(settings.articleListDensity == .comfortable)
    #expect(ArticleListDensity.newspaper.displayName == "Newspaper")
}

@Test func appSettingsAppearanceFallsBackForInvalidRawValues() {
    let settings = AppSettings()
    settings.themeRawValue = "unexpected-theme"
    settings.readerFontRawValue = "unexpected-font"
    settings.articleListDensityRawValue = "unexpected-density"

    #expect(settings.themeChoice == .system)
    #expect(settings.readerFontChoice == .system)
    #expect(settings.articleListDensity == .comfortable)
}

@Test func appSettingsReaderFontSizeIsClamped() {
    let settings = AppSettings()

    settings.clampReaderFontSize(2)
    #expect(settings.readerFontSize == 13)

    settings.clampReaderFontSize(99)
    #expect(settings.readerFontSize == 26)

    settings.clampReaderFontSize(19)
    #expect(settings.readerFontSize == 19)
}
