import Foundation

public enum HTMLTextExtractor {
    public static func text(fromHTML html: String?) -> String? {
        guard let html, !html.isEmpty else { return nil }

        var text = html
            .replacingOccurrences(of: "(?i)<br\\s*/?>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</p>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'"
        ]

        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }

    public static func text(fromHTML html: String) -> String {
        text(fromHTML: Optional(html)) ?? ""
    }
}

