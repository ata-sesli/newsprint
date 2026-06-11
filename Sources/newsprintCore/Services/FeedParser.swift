import Foundation

public enum FeedParserError: Error, LocalizedError {
    case unsupportedFormat
    case invalidJSONFeed
    case invalidXML

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Unsupported feed format"
        case .invalidJSONFeed: "Invalid JSON Feed"
        case .invalidXML: "Invalid XML feed"
        }
    }
}

public struct FeedParser {
    public init() {}

    public func parse(data: Data, source: Source) throws -> [ArticleDraft] {
        if source.kind == .jsonFeed || data.firstNonWhitespaceByte == UInt8(ascii: "{") {
            return try parseJSONFeed(data: data, source: source)
        }

        guard let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw FeedParserError.invalidXML
        }

        if xml.range(of: "<rss", options: .caseInsensitive) != nil {
            return try parseXML(data: data, source: source, format: .rss)
        }

        if xml.range(of: "<feed", options: .caseInsensitive) != nil {
            return try parseXML(data: data, source: source, format: .atom)
        }

        throw FeedParserError.unsupportedFormat
    }

    private func parseJSONFeed(data: Data, source: Source) throws -> [ArticleDraft] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else {
            throw FeedParserError.invalidJSONFeed
        }

        return items.compactMap { item in
            let id = item["id"] as? String
            let title = (item["title"] as? String) ?? "Untitled"
            let urlString = (item["url"] as? String) ?? (item["external_url"] as? String)
            guard let urlString, let url = URL(string: urlString) else {
                return nil
            }

            let authorObject = item["author"] as? [String: Any]
            let author = authorObject?["name"] as? String
            let contentHTML = item["content_html"] as? String
            let contentText = (item["content_text"] as? String) ?? HTMLTextExtractor.text(fromHTML: contentHTML)
            let excerpt = item["summary"] as? String

            return ArticleDraft(
                sourceID: source.id,
                sourceTitle: source.title,
                title: title.trimmedFeedText(defaultValue: "Untitled"),
                url: url,
                author: author?.trimmedOptional,
                publishedAt: DateParser.parse(item["date_published"] as? String),
                updatedAt: DateParser.parse(item["date_modified"] as? String),
                excerpt: excerpt?.trimmedOptional,
                contentHTML: contentHTML,
                contentText: contentText?.trimmedOptional,
                externalID: id?.trimmedOptional
            )
        }
    }

    private func parseXML(data: Data, source: Source, format: XMLFeedFormat) throws -> [ArticleDraft] {
        let delegate = FeedXMLParserDelegate(source: source, format: format)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            throw FeedParserError.invalidXML
        }

        return delegate.drafts
    }
}

private enum XMLFeedFormat {
    case rss
    case atom
}

private final class FeedXMLParserDelegate: NSObject, XMLParserDelegate {
    let source: Source
    let format: XMLFeedFormat
    var drafts: [ArticleDraft] = []
    private var currentItem: [String: String]?
    private var currentElement = ""
    private var currentText = ""
    private var atomLinkHref: String?
    private var insideAuthor = false

    init(source: Source, format: XMLFeedFormat) {
        self.source = source
        self.format = format
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = elementName.lowercased()
        currentElement = element
        currentText = ""

        if (format == .rss && element == "item") || (format == .atom && element == "entry") {
            currentItem = [:]
            atomLinkHref = nil
        }

        if format == .atom && element == "author" {
            insideAuthor = true
        }

        if format == .atom && element == "link", currentItem != nil, atomLinkHref == nil {
            let rel = attributeDict["rel"]?.lowercased()
            if rel == nil || rel == "alternate" {
                atomLinkHref = attributeDict["href"]
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.lowercased()
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if var item = currentItem, !value.isEmpty {
            switch (format, element) {
            case (.rss, "title"), (.rss, "link"), (.rss, "guid"), (.rss, "author"), (.rss, "pubdate"), (.rss, "description"), (.rss, "content:encoded"):
                item[element] = value
                currentItem = item
            case (.atom, "title"), (.atom, "id"), (.atom, "updated"), (.atom, "published"), (.atom, "summary"), (.atom, "content"):
                item[element] = value
                currentItem = item
            case (.atom, "name") where insideAuthor:
                item["author"] = value
                currentItem = item
            default:
                break
            }
        }

        if format == .atom && element == "author" {
            insideAuthor = false
        }

        if (format == .rss && element == "item") || (format == .atom && element == "entry") {
            if let draft = makeDraft(from: currentItem ?? [:]) {
                drafts.append(draft)
            }
            currentItem = nil
            atomLinkHref = nil
        }

        currentText = ""
    }

    private func makeDraft(from item: [String: String]) -> ArticleDraft? {
        let title = item["title"].trimmedFeedText(defaultValue: "Untitled")
        let link = item["link"] ?? atomLinkHref
        guard let link, let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        let html = item["content:encoded"] ?? item["content"] ?? item["description"] ?? item["summary"]
        let contentText = HTMLTextExtractor.text(fromHTML: html)

        return ArticleDraft(
            sourceID: source.id,
            sourceTitle: source.title,
            title: title,
            url: url,
            author: (item["author"] ?? item["name"])?.trimmedOptional,
            publishedAt: DateParser.parse(item["pubdate"] ?? item["published"]),
            updatedAt: DateParser.parse(item["updated"]),
            excerpt: HTMLTextExtractor.text(fromHTML: item["description"] ?? item["summary"]),
            contentHTML: html,
            contentText: contentText,
            externalID: (item["guid"] ?? item["id"])?.trimmedOptional
        )
    }
}

private extension Data {
    var firstNonWhitespaceByte: UInt8? {
        first { byte in
            byte != UInt8(ascii: " ") &&
            byte != UInt8(ascii: "\n") &&
            byte != UInt8(ascii: "\r") &&
            byte != UInt8(ascii: "\t")
        }
    }
}

private extension Optional where Wrapped == String {
    func trimmedFeedText(defaultValue: String) -> String {
        switch self?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case let value? where !value.isEmpty: value
        default: defaultValue
        }
    }
}

private extension String {
    func trimmedFeedText(defaultValue: String) -> String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? defaultValue : value
    }

    var trimmedOptional: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
