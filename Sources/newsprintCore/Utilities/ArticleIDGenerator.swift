import CryptoKit
import Foundation

public enum ArticleIDGenerator {
    public static func id(for draft: ArticleDraft) -> String {
        let canonicalURL = URLCanonicalizer.canonicalize(draft.url)

        if isHTTP(canonicalURL) {
            return canonicalURL.absoluteString
        }

        if isHTTP(draft.url) {
            return draft.url.absoluteString
        }

        if let externalID = draft.externalID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !externalID.isEmpty {
            return externalID
        }

        let published = draft.publishedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        let raw = "\(draft.sourceID.uuidString)|\(draft.title)|\(published)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isHTTP(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}

