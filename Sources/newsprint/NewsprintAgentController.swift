import Foundation
import SwiftData
import newsprintCore

@MainActor
final class NewsprintAgentController: ObservableObject {
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var backgroundRefreshMinutes: Int?

    private var modelContext: ModelContext?
    private var refreshLoopTask: Task<Void, Never>?
    private var didBootstrap = false

    deinit {
        refreshLoopTask?.cancel()
    }

    func bootstrap(container: ModelContainer) {
        guard !didBootstrap else { return }
        didBootstrap = true

        let context = ModelContext(container)
        modelContext = context

        do {
            let settings = try SettingsRepository.loadOrCreate(in: context)
            startBackgroundRefresh(minutes: settings.refreshWhileOpenMinutes)
            statusMessage = nil
        } catch {
            statusMessage = "Could not start background refresh: \(error.localizedDescription)"
        }
    }

    func refreshAll() {
        guard !isRefreshing else { return }
        guard let modelContext else {
            statusMessage = "Newsprint data store is not ready."
            return
        }

        isRefreshing = true
        statusMessage = "Refreshing feeds..."

        Task { @MainActor in
            await FeedRefreshService(context: modelContext).refreshAll()
            lastRefreshAt = Date()
            isRefreshing = false
            statusMessage = nil
            NotificationCenter.default.post(name: .newsprintDataChanged, object: nil)
        }
    }

    func startBackgroundRefresh(minutes: Int?) {
        refreshLoopTask?.cancel()
        backgroundRefreshMinutes = minutes

        guard let minutes else { return }

        refreshLoopTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(minutes * 60))
                if !Task.isCancelled {
                    refreshAll()
                }
            }
        }
    }

    func updateRefreshInterval(minutes: Int?) {
        startBackgroundRefresh(minutes: minutes)
    }

    var lastRefreshText: String {
        guard let lastRefreshAt else {
            return "Last Refresh: Never"
        }
        return "Last Refresh: \(lastRefreshAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var backgroundRefreshText: String {
        guard let backgroundRefreshMinutes else {
            return "Background Refresh: Off"
        }
        return "Background Refresh: Every \(backgroundRefreshMinutes) min"
    }
}
