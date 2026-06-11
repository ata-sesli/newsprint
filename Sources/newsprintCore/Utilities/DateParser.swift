import Foundation

public enum DateParser {
    private static let rfc822Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    public static func parse(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        return rfc822Formatter.date(from: value)
    }
}

