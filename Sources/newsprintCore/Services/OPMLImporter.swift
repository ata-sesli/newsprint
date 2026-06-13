import Foundation

public struct OPMLImportedSource: Hashable, Sendable {
    public let title: String
    public let feedURL: URL
    public let siteURL: URL?
    public let category: String?
    public let kind: SourceKind

    public init(title: String, feedURL: URL, siteURL: URL?, category: String?, kind: SourceKind) {
        self.title = title
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.category = category
        self.kind = kind
    }
}

public struct OPMLImportPreview: Sendable {
    public let sources: [OPMLImportedSource]

    public init(sources: [OPMLImportedSource]) {
        self.sources = sources
    }
}

public struct OPMLImportResult: Sendable {
    public let importedCount: Int
    public let skippedDuplicateCount: Int

    public init(importedCount: Int, skippedDuplicateCount: Int) {
        self.importedCount = importedCount
        self.skippedDuplicateCount = skippedDuplicateCount
    }
}

public enum OPMLImportError: Error, LocalizedError {
    case invalidOPML

    public var errorDescription: String? {
        switch self {
        case .invalidOPML: "Invalid OPML file"
        }
    }
}

public struct OPMLImporter {
    public init() {}

    public func preview(data: Data) throws -> OPMLImportPreview {
        let delegate = OPMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            throw OPMLImportError.invalidOPML
        }

        return OPMLImportPreview(sources: delegate.sources)
    }
}

private final class OPMLParserDelegate: NSObject, XMLParserDelegate {
    var sources: [OPMLImportedSource] = []
    private var categoryStack: [String] = []
    private var outlinePushedCategoryStack: [Bool] = []
    private var seenURLs: Set<String> = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }

        let xmlURLString = attributeDict["xmlUrl"] ?? attributeDict["xmlurl"]
        if let xmlURLString,
           let feedURL = URL(string: xmlURLString),
           seenURLs.insert(URLCanonicalizer.canonicalize(feedURL).absoluteString).inserted {
            let title = attributeDict["title"] ?? attributeDict["text"] ?? feedURL.host() ?? feedURL.absoluteString
            let siteURLString = attributeDict["htmlUrl"] ?? attributeDict["htmlurl"]
            let kind = kind(from: attributeDict["type"], url: feedURL)
            sources.append(OPMLImportedSource(
                title: title,
                feedURL: feedURL,
                siteURL: siteURLString.flatMap(URL.init(string:)),
                category: categoryStack.last,
                kind: kind
            ))
            outlinePushedCategoryStack.append(false)
        } else if xmlURLString != nil {
            outlinePushedCategoryStack.append(false)
        } else if let text = attributeDict["title"] ?? attributeDict["text"], !text.isEmpty {
            categoryStack.append(text)
            outlinePushedCategoryStack.append(true)
        } else {
            outlinePushedCategoryStack.append(false)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "outline",
              let pushedCategory = outlinePushedCategoryStack.popLast(),
              pushedCategory,
              !categoryStack.isEmpty else {
            return
        }
        categoryStack.removeLast()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        categoryStack.removeAll()
        outlinePushedCategoryStack.removeAll()
    }

    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
        categoryStack.removeAll()
        outlinePushedCategoryStack.removeAll()
    }

    private func kind(from type: String?, url: URL) -> SourceKind {
        let lowerType = type?.lowercased()
        if lowerType == "atom" { return .atom }
        if lowerType == "json" || url.pathExtension.lowercased() == "json" { return .jsonFeed }
        return .rss
    }
}
