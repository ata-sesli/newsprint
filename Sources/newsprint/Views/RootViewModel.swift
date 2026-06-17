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

    @discardableResult
    func saveArticleState(_ article: Article, mutation: ArticleStateMutation, context: ModelContext) -> Bool {
        let snapshot = ArticleStateSnapshot(article: article)
        do {
            try mutation.apply(
                to: article,
                repository: SwiftDataArticleRepository(context: context)
            )
            errorMessage = nil
            return true
        } catch {
            snapshot.restore(article)
            errorMessage = "Could not save article: \(error.localizedDescription)"
            return false
        }
    }
}
