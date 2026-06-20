import Foundation
import SwiftData
import newsprintCore

@MainActor
final class NewsprintAgentController: ObservableObject {
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var backgroundRefreshMinutes: Int?
    @Published private(set) var menuBarIconRawValue: String

    private(set) var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    private var refreshActor: FeedRefreshActor?
    private var refreshLoopTask: Task<Void, Never>?
    private var didBootstrap = false

    init() {
        menuBarIconRawValue = MenuBarIconChoice(
            storedRawValue: UserDefaults.standard.string(forKey: MenuBarIconChoice.storageKey)
        ).rawValue
    }

    deinit {
        refreshLoopTask?.cancel()
    }

    func bootstrap(container: ModelContainer) {
        guard !didBootstrap else { return }
        didBootstrap = true

        let context = ModelContext(container)
        modelContainer = container
        modelContext = context
        refreshActor = FeedRefreshActor(modelContainer: container)

        do {
            let settings = try SettingsRepository.loadOrCreate(in: context)
            startBackgroundRefresh(minutes: settings.refreshWhileOpenMinutes)
            statusMessage = nil
        } catch {
            statusMessage = "Could not start background refresh: \(error.localizedDescription)"
        }
    }

    func refreshAll(origin: FeedRefreshOrigin = .manual) {
        guard !isRefreshing else { return }
        guard let refreshActor else {
            statusMessage = "Newsprint data store is not ready."
            return
        }

        isRefreshing = true
        statusMessage = "Refreshing feeds..."

        Task { @MainActor in
            let summary = await refreshActor.refreshAll { [weak self] phase in
                await MainActor.run {
                    self?.statusMessage = phase.statusMessage
                }
            }
            NotificationCenter.default.post(
                name: .newsprintDataChanged,
                object: FeedRefreshEvent(summary: summary, origin: origin)
            )
            lastRefreshAt = Date()
            isRefreshing = false
            statusMessage = summary.failedCount > 0
                ? "Refresh finished with \(summary.failedCount) failed source\(summary.failedCount == 1 ? "" : "s")."
                : nil
        }
    }

    func refresh(sourceID: UUID) {
        guard !isRefreshing else { return }
        guard let refreshActor else {
            statusMessage = "Newsprint data store is not ready."
            return
        }

        isRefreshing = true
        statusMessage = "Refreshing source..."

        Task { @MainActor in
            let summary = await refreshActor.refresh(sourceID: sourceID)
            NotificationCenter.default.post(name: .newsprintDataChanged, object: summary)
            lastRefreshAt = Date()
            isRefreshing = false
            statusMessage = summary.errorMessage
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
                    refreshAll(origin: .automatic)
                }
            }
        }
    }

    func updateRefreshInterval(minutes: Int?) {
        startBackgroundRefresh(minutes: minutes)
    }

    func updateMenuBarIcon(rawValue: String) {
        let icon = MenuBarIconChoice(storedRawValue: rawValue)
        menuBarIconRawValue = icon.rawValue
        UserDefaults.standard.set(icon.rawValue, forKey: MenuBarIconChoice.storageKey)
    }

    var effectiveMenuBarSystemImage: String {
        MenuBarIconResolver.effectiveSystemImage(
            baseIconRawValue: menuBarIconRawValue,
            isRefreshing: isRefreshing,
            hasSyncError: statusMessage != nil && !isRefreshing
        )
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
