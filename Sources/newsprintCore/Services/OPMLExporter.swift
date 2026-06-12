import Foundation

public struct OPMLExporter {
    public init() {}

    public func export(sources: [Source], title: String = "Newsprint Sources") throws -> Data {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <head>
        <title>\(escape(title))</title>
        </head>
        <body>

        """

        let grouped = Dictionary(grouping: sources.sorted { $0.title < $1.title }) { source in
            source.category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        for category in grouped.keys.compactMap({ $0 }).sorted() {
            xml += "<outline text=\"\(escape(category))\">\n"
            for source in grouped[category] ?? [] {
                xml += outline(for: source)
            }
            xml += "</outline>\n"
        }

        for source in grouped[nil] ?? [] {
            xml += outline(for: source)
        }

        xml += """
        </body>
        </opml>

        """

        return Data(xml.utf8)
    }

    private func outline(for source: Source) -> String {
        var attributes = [
            "text=\"\(escape(source.title))\"",
            "title=\"\(escape(source.title))\"",
            "type=\"\(opmlType(for: source.kind))\"",
            "xmlUrl=\"\(escape(source.url.absoluteString))\""
        ]
        if let siteURL = source.siteURL {
            attributes.append("htmlUrl=\"\(escape(siteURL.absoluteString))\"")
        }
        return "<outline \(attributes.joined(separator: " ")) />\n"
    }

    private func opmlType(for kind: SourceKind) -> String {
        switch kind {
        case .atom: "atom"
        case .jsonFeed: "json"
        default: "rss"
        }
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

