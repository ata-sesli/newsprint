import AppKit
import SwiftData
import SwiftUI
import newsprintCore

@main
struct NewsprintApp: App {
    private let startupState: StartupState

    init() {
        startupState = Self.makeStartupState()
        configureDockIcon()
    }

    var body: some Scene {
        WindowGroup {
            switch startupState {
            case .ready(let modelContainer):
                RootView()
                    .modelContainer(modelContainer)
            case .failed(let message, let storeURL):
                StartupErrorView(message: message, storeURL: storeURL)
            }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Source") {
                    NotificationCenter.default.post(name: .newsprintAddSource, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Refresh All") {
                    NotificationCenter.default.post(name: .newsprintRefreshAll, object: nil)
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
    }

    private func configureDockIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApplication.shared.applicationIconImage = image
    }

    private static func makeStartupState() -> StartupState {
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
            return .ready(try ModelContainer(for: schema, configurations: [configuration]))
        } catch {
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
    static let newsprintFocusSearch = Notification.Name("newsprintFocusSearch")
    static let newsprintToggleRead = Notification.Name("newsprintToggleRead")
    static let newsprintToggleStar = Notification.Name("newsprintToggleStar")
    static let newsprintToggleHidden = Notification.Name("newsprintToggleHidden")
    static let newsprintOpenOriginal = Notification.Name("newsprintOpenOriginal")
    static let newsprintTogglePreviewPane = Notification.Name("newsprintTogglePreviewPane")
}
