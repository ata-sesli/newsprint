import Foundation
import SwiftData

@MainActor
public final class FeedRefreshService {
    private let sourceRepository: SwiftDataSourceRepository
    private let articleRepository: SwiftDataArticleRepository
    private let httpClient: FeedHTTPClient
    private let parser: FeedParser

    public init(
        context: ModelContext,
        httpClient: FeedHTTPClient = FeedHTTPClient(),
        parser: FeedParser = FeedParser()
    ) {
        self.sourceRepository = SwiftDataSourceRepository(context: context)
        self.articleRepository = SwiftDataArticleRepository(context: context)
        self.httpClient = httpClient
        self.parser = parser
    }

    public func refreshAll() async {
        do {
            let sources = try sourceRepository.enabledSources()
            for source in sources {
                await refresh(source: source)
            }
        } catch {
            // Source load failures are surfaced through individual source errors in the UI where possible.
        }
    }

    public func refresh(source: Source) async {
        do {
            try sourceRepository.markFetchStarted(source)
            let response = try await httpClient.fetch(source: source)

            if response.isNotModified {
                try sourceRepository.markFetchSucceeded(source, response: response)
                return
            }

            let drafts = try parser.parse(data: response.data, source: source)
            for draft in drafts {
                try articleRepository.insertIfNew(Article(draft: draft))
            }

            try sourceRepository.markFetchSucceeded(source, response: response)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            try? sourceRepository.markFetchFailed(source, message: message)
        }
    }
}

