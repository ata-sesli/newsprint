import SwiftUI
import newsprintCore

struct SidebarView: View {
    @Environment(\.newsprintTheme) private var theme
    @Binding var selection: SidebarSelection
    let sources: [Source]
    let articles: [Article]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !tagNames.isEmpty {
                    SidebarSection("Tags") {
                        ForEach(tagNames, id: \.self) { tag in
                            SidebarRow(
                                title: tag,
                                systemImage: "tag",
                                isSelected: selection == .tag(tag)
                            ) {
                                selection = .tag(tag)
                            }
                        }
                    }
                }

                SidebarRow(
                    title: "Home",
                    systemImage: "house",
                    isSelected: selection == .inbox
                ) {
                    selection = .inbox
                }

                SidebarSection("Manage") {
                    SidebarRow(
                        title: "Sources",
                        systemImage: "slider.horizontal.3",
                        isSelected: selection == .sources
                    ) {
                        selection = .sources
                    }
                    SidebarRow(
                        title: "Rules",
                        systemImage: "line.3.horizontal.decrease.circle",
                        isSelected: selection == .rules
                    ) {
                        selection = .rules
                    }
                    SidebarRow(
                        title: "Settings",
                        systemImage: "gearshape",
                        isSelected: selection == .settings
                    ) {
                        selection = .settings
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
        }
        .scrollContentBackground(.hidden)
        .background(theme.paneBackground)
        .navigationTitle("Newsprint")
    }

    private var tagNames: [String] {
        Array(Set(articles.flatMap(\.tagNames))).sorted()
    }
}

private struct SidebarSection<Content: View>: View {
    @Environment(\.newsprintTheme) private var theme
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.metadata)
                .padding(.horizontal, 8)

            VStack(spacing: 5) {
                content
            }
        }
    }
}

private struct SidebarRow: View {
    @Environment(\.newsprintTheme) private var theme
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.white : theme.tint)

                Text(title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : .primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        isSelected ? theme.tint : theme.readerSurface.opacity(0.34)
    }

    private var borderColor: Color {
        isSelected ? theme.tint.opacity(0.75) : Color(nsColor: .separatorColor).opacity(0.18)
    }
}
