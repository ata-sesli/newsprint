import Foundation
import SwiftData
import newsprintCore

@MainActor
final class RootViewModel: ObservableObject {
    @Published var sources: [Source] = []
    @Published var errorMessage: String?

    private var didBootstrap = false

    func bootstrap(context: ModelContext, settings: AppSettings?, onDataChanged: @escaping () -> Void = {}) {
        guard !didBootstrap else {
            reloadSources(context: context)
            return
        }
        didBootstrap = true

        do {
            let timing = StartupTimingRecorder()
            _ = try settings ?? SettingsRepository.loadOrCreate(in: context)
            timing.markAndLog("Settings load")
            reloadSources(context: context)
            timing.markAndLog("Source load")
            onDataChanged()
        } catch {
            errorMessage = "Could not load app data: \(error.localizedDescription)"
        }
    }

    func reloadSources(context: ModelContext) {
        do {
            sources = try context.fetch(FetchDescriptor<Source>(
                sortBy: [SortDescriptor(\Source.title)]
            ))
            errorMessage = nil
        } catch {
            errorMessage = "Could not load sources: \(error.localizedDescription)"
        }
    }

    func noteSourceInserted(_ source: Source) {
        guard !sources.contains(where: { $0.id == source.id }) else {
            return
        }
        sources.append(source)
        sources.sort {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        errorMessage = nil
    }

    @discardableResult
    func saveArticleState(articleID: String, mutation: ArticleStateMutation, context: ModelContext) -> ArticleFeedSnapshotMutation? {
        guard let article = article(id: articleID, context: context) else {
            errorMessage = "Could not save article: article not found."
            return nil
        }
        let snapshot = ArticleStateSnapshot(article: article)
        do {
            try mutation.apply(
                to: article,
                repository: SwiftDataArticleRepository(context: context)
            )
            errorMessage = nil
            return ArticleFeedSnapshotMutation(
                isRead: article.isRead,
                isStarred: article.isStarred,
                isHidden: article.isHidden
            )
        } catch {
            snapshot.restore(article)
            errorMessage = "Could not save article: \(error.localizedDescription)"
            return nil
        }
    }

    private func article(id articleID: String, context: ModelContext) -> Article? {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.id == articleID
            }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
