import AppKit
import SwiftData
import SwiftUI
import newsprintCore

@main
struct NewsprintApp: App {
    @NSApplicationDelegateAdaptor(NewsprintAppDelegate.self) private var appDelegate
    private let startupState: StartupState
    private let agentController: NewsprintAgentController
    private let dashboardController: NewsprintDashboardController

    @MainActor
    init() {
        let agentController = NewsprintAgentController()
        self.agentController = agentController
        startupState = Self.makeStartupState()
        dashboardController = NewsprintDashboardController(
            startupState: startupState,
            agentController: agentController
        )
        if case .ready(let modelContainer) = startupState {
            agentController.bootstrap(container: modelContainer)
        }
        configureDockIcon()
    }

    @SceneBuilder
    var body: some Scene {
        MenuBarExtra("Newsprint", systemImage: "newspaper") {
            NewsprintMenuBarView(
                startupState: startupState,
                agentController: agentController,
                dashboardController: dashboardController
            )
        }
        .menuBarExtraStyle(.menu)
        .commands {
            appCommands
        }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Source") {
                dashboardController.openDashboard()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .newsprintAddSource, object: nil)
                }
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Refresh All") {
                agentController.refreshAll()
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(after: .textEditing) {
            Button("Search") {
                NotificationCenter.default.post(name: .newsprintFocusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Preview Pane") {
                NotificationCenter.default.post(name: .newsprintTogglePreviewPane, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

            Button("Mark Read/Unread") {
                NotificationCenter.default.post(name: .newsprintToggleRead, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Star/Unstar") {
                NotificationCenter.default.post(name: .newsprintToggleStar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [])

            Button("Hide/Unhide") {
                NotificationCenter.default.post(name: .newsprintToggleHidden, object: nil)
            }
            .keyboardShortcut("h", modifiers: [])

            Button("Open Original") {
                NotificationCenter.default.post(name: .newsprintOpenOriginal, object: nil)
            }
            .keyboardShortcut("o", modifiers: [])
        }
    }

    private func configureDockIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApplication.shared.applicationIconImage = image
    }

    private static func makeStartupState() -> StartupState {
        let timing = StartupTimingRecorder()
        let storeURL = storeURL()
        do {
            let schema = Schema([
                Source.self,
                Article.self,
                AppSettings.self,
                FilterRule.self
            ])
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let configuration = ModelConfiguration(
                schema: schema,
                url: storeURL
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            timing.markAndLog("Model container creation")
            return .ready(container)
        } catch {
            timing.markAndLog("Model container creation failed")
            return .failed(
                message: "Could not open the Newsprint database: \(error.localizedDescription)",
                storeURL: storeURL
            )
        }
    }

    private static func storeURL() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "newsprint/newsprint.store")
    }
}

@MainActor
final class NewsprintAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class NewsprintDashboardController: NSObject, NSWindowDelegate {
    private let startupState: StartupState
    private let agentController: NewsprintAgentController
    private var window: NSWindow?

    init(startupState: StartupState, agentController: NewsprintAgentController) {
        self.startupState = startupState
        self.agentController = agentController
        super.init()
    }

    func openDashboard() {
        NSApp.setActivationPolicy(.regular)
        let window = dashboardWindow()
        maximize(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dashboardWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1800, height: 1100),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Newsprint"
        window.contentViewController = NSHostingController(rootView: dashboardContent)
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        return window
    }

    private var dashboardContent: some View {
        Group {
            switch startupState {
            case .ready(let modelContainer):
                RootView()
                    .environmentObject(agentController)
                    .modelContainer(modelContainer)
            case .failed(let message, let storeURL):
                StartupErrorView(message: message, storeURL: storeURL)
            }
        }
    }

    private func maximize(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        window.setFrame(screen.visibleFrame, display: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}

private struct NewsprintMenuBarView: View {
    let startupState: StartupState
    @ObservedObject var agentController: NewsprintAgentController
    let dashboardController: NewsprintDashboardController

    var body: some View {
        Button("Open Newsprint", systemImage: "newspaper") {
            dashboardController.openDashboard()
        }

        Divider()

        Button("Refresh Feeds", systemImage: "arrow.clockwise") {
            agentController.refreshAll()
        }
        .disabled(!canRefresh || agentController.isRefreshing)

        Text(agentController.lastRefreshText)
            .disabled(true)
        Text(agentController.backgroundRefreshText)
            .disabled(true)

        if let statusMessage = agentController.statusMessage {
            Text(statusMessage)
                .disabled(true)
        }

        Divider()

        Button("Quit Newsprint", systemImage: "power") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var canRefresh: Bool {
        if case .ready = startupState {
            return true
        }
        return false
    }
}

enum StartupState {
    case ready(ModelContainer)
    case failed(message: String, storeURL: URL)
}

struct StartupErrorView: View {
    let message: String
    let storeURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Newsprint Could Not Start", systemImage: "exclamationmark.triangle")
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(storeURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(28)
        .frame(minWidth: 520, minHeight: 220, alignment: .leading)
    }
}

extension Notification.Name {
    static let newsprintRefreshAll = Notification.Name("newsprintRefreshAll")
    static let newsprintAddSource = Notification.Name("newsprintAddSource")
    static let newsprintDataChanged = Notification.Name("newsprintDataChanged")
    static let newsprintOpenDashboard = Notification.Name("newsprintOpenDashboard")
    static let newsprintHideDashboard = Notification.Name("newsprintHideDashboard")
    static let newsprintFocusSearch = Notification.Name("newsprintFocusSearch")
    static let newsprintToggleRead = Notification.Name("newsprintToggleRead")
    static let newsprintToggleStar = Notification.Name("newsprintToggleStar")
    static let newsprintToggleHidden = Notification.Name("newsprintToggleHidden")
    static let newsprintOpenOriginal = Notification.Name("newsprintOpenOriginal")
    static let newsprintTogglePreviewPane = Notification.Name("newsprintTogglePreviewPane")
}
