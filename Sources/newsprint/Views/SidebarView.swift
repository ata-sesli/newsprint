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
                Label("Today", systemImage: "calendar")
                    .tag(SidebarSelection.today)
                Label("Starred", systemImage: "star")
                    .tag(SidebarSelection.starred)
                Label("Hidden", systemImage: "eye.slash")
                    .tag(SidebarSelection.hidden)
            }

            if !tagNames.isEmpty {
                Section("Tags") {
                    ForEach(tagNames, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .tag(SidebarSelection.tag(tag))
                    }
                }
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
                Label("Rules", systemImage: "line.3.horizontal.decrease.circle")
                    .tag(SidebarSelection.rules)
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
            }
        }
        .navigationTitle("Newsprint")
    }

    private var tagNames: [String] {
        Array(Set(articles.flatMap(\.tagNames))).sorted()
    }
}
