import Foundation
import OSLog

public enum NewsprintLog {
    public static let startup = Logger(subsystem: "Newsprint", category: "startup")
    public static let feed = Logger(subsystem: "Newsprint", category: "feed")
    public static let discovery = Logger(subsystem: "Newsprint", category: "discovery")
    public static let rules = Logger(subsystem: "Newsprint", category: "rules")
    public static let retention = Logger(subsystem: "Newsprint", category: "retention")
    public static let storage = Logger(subsystem: "Newsprint", category: "storage")
    public static let ui = Logger(subsystem: "Newsprint", category: "ui")
}

public enum SourceErrorFormatter {
    public static func message(for error: Error) -> String {
        if let httpError = error as? FeedHTTPError {
            switch httpError {
            case .invalidResponse:
                return "Network error: invalid server response"
            case .httpStatus(let code) where (500...599).contains(code):
                return "Server error: HTTP \(code)"
            case .httpStatus(let code):
                return "Network error: HTTP \(code)"
            }
        }

        if let parserError = error as? FeedParserError {
            return "Parsing error: \(parserError.errorDescription ?? "Invalid feed")"
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "Timeout: the feed did not respond in time"
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                return "Network error: \(urlError.localizedDescription)"
            default:
                return "Network error: \(urlError.localizedDescription)"
            }
        }

        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
