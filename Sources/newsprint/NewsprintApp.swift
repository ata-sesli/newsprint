import SwiftData
import SwiftUI
import newsprintCore

@main
struct NewsprintApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Source.self,
            Article.self,
            AppSettings.self
        ])
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh All") {
                    NotificationCenter.default.post(name: .newsprintRefreshAll, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let newsprintRefreshAll = Notification.Name("newsprintRefreshAll")
}

