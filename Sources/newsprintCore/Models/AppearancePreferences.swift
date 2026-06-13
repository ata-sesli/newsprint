import Foundation

public enum AppThemeChoice: String, Codable, CaseIterable, Sendable {
    case system
    case newsprintLight
    case inkDark
    case sepia

    public var displayName: String {
        switch self {
        case .system:
            "System"
        case .newsprintLight:
            "Newsprint Light"
        case .inkDark:
            "Ink Dark"
        case .sepia:
            "Sepia"
        }
    }
}

public enum ReaderFontChoice: String, Codable, CaseIterable, Sendable {
    case system
    case serif
    case rounded
    case monospaced

    public var displayName: String {
        switch self {
        case .system:
            "System"
        case .serif:
            "Serif"
        case .rounded:
            "Rounded"
        case .monospaced:
            "Monospaced"
        }
    }
}

public enum ArticleListDensity: String, Codable, CaseIterable, Sendable {
    case comfortable
    case compact

    public var displayName: String {
        switch self {
        case .comfortable:
            "Comfortable"
        case .compact:
            "Compact"
        }
    }
}
