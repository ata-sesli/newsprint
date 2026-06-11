import Foundation

public enum URLCanonicalizer {
    private static let trackingParameters: Set<String> = [
        "utm_source",
        "utm_medium",
        "utm_campaign",
        "utm_content",
        "utm_term",
        "ref",
        "fbclid",
        "gclid",
        "mc_cid",
        "mc_eid"
    ]

    public static func canonicalize(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return url
        }

        components.scheme = scheme
        components.host = components.host?.lowercased()

        let filteredItems = components.queryItems?
            .filter { !trackingParameters.contains($0.name.lowercased()) }
            .sorted { lhs, rhs in lhs.name == rhs.name ? (lhs.value ?? "") < (rhs.value ?? "") : lhs.name < rhs.name }

        components.queryItems = filteredItems?.isEmpty == true ? nil : filteredItems
        return components.url ?? url
    }
}

