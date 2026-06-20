import Foundation

public enum MenuBarIconChoice: String, Codable, CaseIterable, Sendable {
    case newspaper = "newspaper.fill"
    case terminal = "terminal.fill"
    case stack = "square.stack.3d.up.fill"
    case signal = "dot.radiowaves.up.forward"

    public static let defaultChoice: MenuBarIconChoice = .newspaper
    public static let storageKey = "newsprint.menuBarIcon"

    public init(storedRawValue: String?) {
        self = storedRawValue.flatMap(Self.init(rawValue:)) ?? Self.defaultChoice
    }

    public var systemImage: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .newspaper:
            "Newspaper"
        case .terminal:
            "Terminal"
        case .stack:
            "Stack"
        case .signal:
            "Signal"
        }
    }
}

public enum MenuBarIconResolver {
    public static func effectiveSystemImage(
        baseIconRawValue: String?,
        isRefreshing: Bool,
        hasSyncError: Bool
    ) -> String {
        if isRefreshing {
            return "arrow.clockwise"
        }
        return MenuBarIconChoice(storedRawValue: baseIconRawValue).systemImage
    }
}
