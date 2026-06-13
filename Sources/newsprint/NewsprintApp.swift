import AppKit
import SwiftData
import SwiftUI
import newsprintCore

@main
struct NewsprintApp: App {
    private let modelContainer: ModelContainer

    init() {
        modelContainer = Self.makeModelContainer()
        configureDockIcon()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
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

                Button("Toggle Reader Pane") {
                    NotificationCenter.default.post(name: .newsprintToggleReaderPane, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
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

    private static func makeModelContainer() -> ModelContainer {
        do {
            let schema = Schema([
                Source.self,
                Article.self,
                AppSettings.self,
                FilterRule.self
            ])
            let applicationSupportURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            let storeDirectory = applicationSupportURL.appending(path: "newsprint")
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

            let configuration = ModelConfiguration(
                schema: schema,
                url: storeDirectory.appending(path: "newsprint.store")
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create Newsprint model container: \(error)")
        }
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
    static let newsprintToggleReaderPane = Notification.Name("newsprintToggleReaderPane")
}
