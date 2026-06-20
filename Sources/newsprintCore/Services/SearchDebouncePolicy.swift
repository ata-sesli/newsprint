import Foundation

public enum SearchDebouncePolicy {
    public static let delayNanoseconds: UInt64 = 100_000_000

    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
