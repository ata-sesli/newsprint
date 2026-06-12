import AppKit
import SwiftData
import SwiftUI
import newsprintCore

@main
struct NewsprintApp: App {
    init() {
        configureDockIcon()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Source.self,
            Article.self,
            AppSettings.self,
            FilterRule.self
        ])
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
}

extension Notification.Name {
    static let newsprintRefreshAll = Notification.Name("newsprintRefreshAll")
    static let newsprintAddSource = Notification.Name("newsprintAddSource")
    static let newsprintFocusSearch = Notification.Name("newsprintFocusSearch")
    static let newsprintToggleRead = Notification.Name("newsprintToggleRead")
    static let newsprintToggleStar = Notification.Name("newsprintToggleStar")
    static let newsprintToggleHidden = Notification.Name("newsprintToggleHidden")
    static let newsprintOpenOriginal = Notification.Name("newsprintOpenOriginal")
}
