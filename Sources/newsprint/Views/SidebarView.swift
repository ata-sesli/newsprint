import SwiftUI
import newsprintCore

struct SidebarView: View {
    @Binding var selection: SidebarSelection
    let sources: [Source]
    let articles: [Article]

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("Inbox", systemImage: "tray")
                    .tag(SidebarSelection.inbox)
                Label("Unread", systemImage: "circle")
                    .tag(SidebarSelection.unread)
                Label("Starred", systemImage: "star")
                    .tag(SidebarSelection.starred)
                Label("Hidden", systemImage: "eye.slash")
                    .tag(SidebarSelection.hidden)
            }

            Section("Sources") {
                ForEach(sources) { source in
                    Label(source.title, systemImage: source.enabled ? "dot.radiowaves.left.and.right" : "pause.circle")
                        .tag(SidebarSelection.source(source.id))
                }
            }

            Section("Manage") {
                Label("Sources", systemImage: "slider.horizontal.3")
                    .tag(SidebarSelection.sources)
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
            }
        }
        .navigationTitle("Newsprint")
    }
}
