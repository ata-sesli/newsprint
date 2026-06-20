import Foundation
import Testing
@testable import newsprintCore

@Test func appSettingsAppearanceDefaults() {
    let settings = AppSettings()

    #expect(settings.themeChoice == .system)
    #expect(settings.readerFontChoice == .system)
    #expect(settings.readerFontSize == 17)
    #expect(settings.articleListDensity == .comfortable)
    #expect(settings.webPreviewHorizontalPadding == 8)
    #expect(settings.refreshWhileOpenMinutes == 60)
    #expect(ArticleListDensity.newspaper.displayName == "Newspaper")
}

@Test func releaseBuildScriptConfiguresMenuBarAgent() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let packageRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let script = try String(contentsOf: packageRoot.appending(path: "scripts/build-release-app.sh"), encoding: .utf8)

    #expect(script.contains("<key>LSUIElement</key>"))
    #expect(script.contains("<true/>"))
}

@Test func appLaunchOpensDashboardWindow() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let packageRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let appSource = try String(contentsOf: packageRoot.appending(path: "Sources/newsprint/NewsprintApp.swift"), encoding: .utf8)

    #expect(appSource.contains("dashboardController?.openDashboardOnLaunch()"))
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

@Test func appSettingsWebPreviewPaddingIsClamped() {
    let settings = AppSettings()

    settings.clampWebPreviewHorizontalPadding(-4)
    #expect(settings.webPreviewHorizontalPadding == 0)

    settings.clampWebPreviewHorizontalPadding(80)
    #expect(settings.webPreviewHorizontalPadding == 32)

    settings.clampWebPreviewHorizontalPadding(8)
    #expect(settings.webPreviewHorizontalPadding == 8)
}

@Test func menuBarIconChoiceDefaultsAndFallsBackToNewspaper() {
    #expect(MenuBarIconChoice.defaultChoice == .newspaper)
    #expect(MenuBarIconChoice(storedRawValue: nil) == .newspaper)
    #expect(MenuBarIconChoice(storedRawValue: "not-a-symbol") == .newspaper)
    #expect(MenuBarIconChoice(storedRawValue: "terminal.fill") == .terminal)
    #expect(MenuBarIconChoice.newspaper.systemImage == "newspaper.fill")
}

@Test func menuBarIconResolverUsesDynamicStatusOverrides() {
    #expect(
        MenuBarIconResolver.effectiveSystemImage(
            baseIconRawValue: "terminal.fill",
            isRefreshing: true,
            hasSyncError: true
        ) == "arrow.clockwise"
    )

    #expect(
        MenuBarIconResolver.effectiveSystemImage(
            baseIconRawValue: "terminal.fill",
            isRefreshing: false,
            hasSyncError: true
        ) == "terminal.fill"
    )

    #expect(
        MenuBarIconResolver.effectiveSystemImage(
            baseIconRawValue: "terminal.fill",
            isRefreshing: false,
            hasSyncError: false
        ) == "terminal.fill"
    )
}
