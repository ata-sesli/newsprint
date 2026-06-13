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
            "&apos;": "'",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\"",
            "&ldquo;": "\"",
            "&ndash;": "-",
            "&mdash;": "-",
            "&hellip;": "...",
            "&copy;": "(c)",
            "&reg;": "(r)",
            "&trade;": "(tm)"
        ]

        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        text = normalizeSmartPunctuation(decodeNumericEntities(in: text))

        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }

    public static func text(fromHTML html: String) -> String {
        text(fromHTML: Optional(html)) ?? ""
    }

    private static func decodeNumericEntities(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9a-fA-F]+);"#) else {
            return text
        }

        var output = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()
        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: output),
                  let valueRange = Range(match.range(at: 1), in: output) else {
                continue
            }

            let rawValue = String(output[valueRange])
            let radix = rawValue.lowercased().hasPrefix("x") ? 16 : 10
            let scalarText = radix == 16 ? String(rawValue.dropFirst()) : rawValue
            guard let codePoint = UInt32(scalarText, radix: radix),
                  let scalar = UnicodeScalar(codePoint) else {
                continue
            }

            output.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return output
    }

    private static func normalizeSmartPunctuation(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2026}", with: "...")
    }
}
