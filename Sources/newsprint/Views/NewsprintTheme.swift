import SwiftUI
import newsprintCore

struct NewsprintTheme: Equatable {
    let choice: AppThemeChoice
    let colorScheme: ColorScheme?
    let tint: Color
    let windowBackground: Color
    let paneBackground: Color
    let readerBackground: Color
    let readerSurface: Color
    let rowAccent: Color
    let metadata: Color

    static func make(_ choice: AppThemeChoice) -> NewsprintTheme {
        switch choice {
        case .system:
            NewsprintTheme(
                choice: choice,
                colorScheme: nil,
                tint: .accentColor,
                windowBackground: Color(nsColor: .windowBackgroundColor),
                paneBackground: Color(nsColor: .controlBackgroundColor),
                readerBackground: Color(nsColor: .textBackgroundColor),
                readerSurface: Color(nsColor: .textBackgroundColor),
                rowAccent: .blue,
                metadata: .secondary
            )
        case .newsprintLight:
            NewsprintTheme(
                choice: choice,
                colorScheme: .light,
                tint: Color(red: 0.10, green: 0.33, blue: 0.48),
                windowBackground: Color(red: 0.94, green: 0.94, blue: 0.90),
                paneBackground: Color(red: 0.98, green: 0.97, blue: 0.93),
                readerBackground: Color(red: 0.94, green: 0.94, blue: 0.90),
                readerSurface: Color(red: 1.00, green: 0.99, blue: 0.95),
                rowAccent: Color(red: 0.78, green: 0.26, blue: 0.12),
                metadata: Color(red: 0.39, green: 0.38, blue: 0.33)
            )
        case .inkDark:
            NewsprintTheme(
                choice: choice,
                colorScheme: .dark,
                tint: Color(red: 0.86, green: 0.54, blue: 0.24),
                windowBackground: Color(red: 0.08, green: 0.09, blue: 0.09),
                paneBackground: Color(red: 0.11, green: 0.12, blue: 0.12),
                readerBackground: Color(red: 0.08, green: 0.09, blue: 0.09),
                readerSurface: Color(red: 0.13, green: 0.14, blue: 0.14),
                rowAccent: Color(red: 0.94, green: 0.70, blue: 0.36),
                metadata: Color(red: 0.70, green: 0.70, blue: 0.66)
            )
        case .sepia:
            NewsprintTheme(
                choice: choice,
                colorScheme: .light,
                tint: Color(red: 0.44, green: 0.25, blue: 0.12),
                windowBackground: Color(red: 0.90, green: 0.84, blue: 0.72),
                paneBackground: Color(red: 0.95, green: 0.89, blue: 0.78),
                readerBackground: Color(red: 0.90, green: 0.84, blue: 0.72),
                readerSurface: Color(red: 0.98, green: 0.93, blue: 0.82),
                rowAccent: Color(red: 0.62, green: 0.31, blue: 0.12),
                metadata: Color(red: 0.46, green: 0.36, blue: 0.25)
            )
        }
    }
}

private struct NewsprintThemeKey: EnvironmentKey {
    static let defaultValue = NewsprintTheme.make(.system)
}

private struct ReaderFontChoiceKey: EnvironmentKey {
    static let defaultValue = ReaderFontChoice.system
}

private struct ReaderFontSizeKey: EnvironmentKey {
    static let defaultValue = 17
}

private struct ArticleListDensityKey: EnvironmentKey {
    static let defaultValue = ArticleListDensity.comfortable
}

extension EnvironmentValues {
    var newsprintTheme: NewsprintTheme {
        get { self[NewsprintThemeKey.self] }
        set { self[NewsprintThemeKey.self] = newValue }
    }

    var readerFontChoice: ReaderFontChoice {
        get { self[ReaderFontChoiceKey.self] }
        set { self[ReaderFontChoiceKey.self] = newValue }
    }

    var readerFontSize: Int {
        get { self[ReaderFontSizeKey.self] }
        set { self[ReaderFontSizeKey.self] = newValue }
    }

    var articleListDensity: ArticleListDensity {
        get { self[ArticleListDensityKey.self] }
        set { self[ArticleListDensityKey.self] = newValue }
    }
}

extension ReaderFontChoice {
    var fontDesign: Font.Design {
        switch self {
        case .system:
            .default
        case .serif:
            .serif
        case .rounded:
            .rounded
        case .monospaced:
            .monospaced
        }
    }
}

extension ArticleListDensity {
    var rowVerticalPadding: CGFloat {
        switch self {
        case .comfortable:
            8
        case .compact:
            4
        case .newspaper:
            18
        }
    }

    var previewLineLimit: Int {
        switch self {
        case .comfortable:
            3
        case .compact:
            2
        case .newspaper:
            6
        }
    }

    var rowSpacing: CGFloat {
        switch self {
        case .comfortable:
            7
        case .compact:
            4
        case .newspaper:
            12
        }
    }

    var cardPadding: CGFloat {
        switch self {
        case .compact:
            14
        case .comfortable:
            18
        case .newspaper:
            28
        }
    }

    var cardCornerRadius: CGFloat {
        switch self {
        case .compact:
            6
        case .comfortable:
            8
        case .newspaper:
            8
        }
    }

    var titleScale: CGFloat {
        switch self {
        case .compact:
            1.05
        case .comfortable:
            1.18
        case .newspaper:
            1.55
        }
    }

    var expandedContentSpacing: CGFloat {
        switch self {
        case .compact:
            12
        case .comfortable:
            16
        case .newspaper:
            24
        }
    }

    var summarySpacing: CGFloat {
        switch self {
        case .compact:
            10
        case .comfortable:
            12
        case .newspaper:
            16
        }
    }
}
