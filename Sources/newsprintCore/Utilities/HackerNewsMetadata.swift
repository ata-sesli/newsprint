import Foundation

public struct HackerNewsMetadata: Equatable, Sendable {
    public let articleURL: URL?
    public let threadURL: URL?
    public let points: Int?
    public let commentCount: Int?
    public let authorComment: String?

    public init?(text: String?) {
        guard let text, text.localizedCaseInsensitiveContains("Comments URL:") else {
            return nil
        }

        self.articleURL = Self.url(after: "Article URL:", in: text)
        self.threadURL = Self.url(after: "Comments URL:", in: text)
        self.points = Self.integer(after: "Points:", in: text)
        self.commentCount = Self.integer(after: "# Comments:", in: text)
        self.authorComment = Self.authorComment(from: text)
    }

    private static func url(after label: String, in text: String) -> URL? {
        guard let range = text.range(of: "\(NSRegularExpression.escapedPattern(for: label))\\s*(\\S+)", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        let matched = String(text[range])
        let value = matched
            .replacingOccurrences(of: label, with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: value)
    }

    private static func integer(after label: String, in text: String) -> Int? {
        guard let range = text.range(of: "\(NSRegularExpression.escapedPattern(for: label))\\s*(\\d+)", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        let matched = String(text[range])
        let digits = matched.filter(\.isNumber)
        return Int(digits)
    }

    private static func authorComment(from text: String) -> String? {
        var cleaned = text
        for pattern in [
            #"Article URL:\s*\S+"#,
            #"Comments URL:\s*\S+"#,
            #"Points:\s*\d+"#,
            #"# Comments:\s*\d+"#
        ] {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }

        let normalized = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

