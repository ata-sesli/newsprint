import Foundation
import SwiftData
import newsprintCore

@MainActor
final class RootViewModel: ObservableObject {
    @Published var sources: [Source] = []
    @Published var errorMessage: String?

    private var didBootstrap = false
    private var refreshTask: Task<Void, Never>?
    private var refreshLoopTask: Task<Void, Never>?

    func bootstrap(context: ModelContext, settings: AppSettings?) {
        guard !didBootstrap else {
            reloadSources(context: context)
            return
        }
        didBootstrap = true

        do {
            let loadedSettings = try settings ?? SettingsRepository.loadOrCreate(in: context)
            reloadSources(context: context)
            if loadedSettings.refreshOnLaunch {
                refreshAll(context: context)
            } else {
                runRetentionCleanup(context: context, settings: loadedSettings)
            }
            startRefreshLoop(context: context, minutes: loadedSettings.refreshWhileOpenMinutes)
        } catch {
            errorMessage = "Could not load app data: \(error.localizedDescription)"
        }
    }

    func refreshAll(context: ModelContext) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            await FeedRefreshService(context: context).refreshAll()
            reloadSources(context: context)
        }
    }

    func refresh(_ source: Source, context: ModelContext) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            await FeedRefreshService(context: context).refresh(source: source)
            reloadSources(context: context)
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

    func saveArticleState(_ article: Article, mutation: ArticleStateMutation, context: ModelContext) {
        let snapshot = ArticleStateSnapshot(article: article)
        do {
            try mutation.apply(
                to: article,
                repository: SwiftDataArticleRepository(context: context)
            )
            errorMessage = nil
        } catch {
            snapshot.restore(article)
            errorMessage = "Could not save article: \(error.localizedDescription)"
        }
    }

    func startRefreshLoop(context: ModelContext, minutes: Int?) {
        refreshLoopTask?.cancel()
        guard let minutes else { return }

        refreshLoopTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(minutes * 60))
                if !Task.isCancelled {
                    refreshAll(context: context)
                }
            }
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
