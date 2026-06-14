import Foundation
import SwiftData
import newsprintCore

@MainActor
final class RootViewModel: ObservableObject {
    @Published var sources: [Source] = []
    @Published var errorMessage: String?

    private var didBootstrap = false
    private var refreshTask: Task<Void, Never>?

    func bootstrap(context: ModelContext, settings: AppSettings?, onDataChanged: @escaping () -> Void = {}) {
        guard !didBootstrap else {
            reloadSources(context: context)
            return
        }
        didBootstrap = true

        do {
            let timing = StartupTimingRecorder()
            let loadedSettings = try settings ?? SettingsRepository.loadOrCreate(in: context)
            timing.markAndLog("Settings load")
            reloadSources(context: context)
            timing.markAndLog("Source load")
            runRetentionCleanup(context: context, settings: loadedSettings)
            onDataChanged()
        } catch {
            errorMessage = "Could not load app data: \(error.localizedDescription)"
        }
    }

    func refreshAll(context: ModelContext, onDataChanged: @escaping () -> Void = {}) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            await FeedRefreshService(context: context).refreshAll()
            reloadSources(context: context)
            onDataChanged()
        }
    }

    func refresh(_ source: Source, context: ModelContext, onDataChanged: @escaping () -> Void = {}) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            await FeedRefreshService(context: context).refresh(source: source)
            reloadSources(context: context)
            onDataChanged()
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

    private func runRetentionCleanup(context: ModelContext, settings: AppSettings) {
        do {
            let result = try RetentionEngine().cleanup(
                context: context,
                retentionDays: settings.retentionDays
            )
            settings.lastRetentionCleanupAt = result.lastCleanupAt
            settings.lastRetentionDeletedCount = result.deletedCount
            try context.save()
            errorMessage = nil
        } catch {
            errorMessage = "Could not run retention cleanup: \(error.localizedDescription)"
        }
    }
}
