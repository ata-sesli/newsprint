import AppKit
import SwiftData
import SwiftUI

struct PersistentTwoPaneSplitView<Sidebar: View, Content: View>: NSViewControllerRepresentable {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    @Environment(\.articleListDensity) private var articleListDensity

    private let sidebar: Sidebar
    private let content: Content

    init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content
    ) {
        self.sidebar = sidebar()
        self.content = content()
    }

    func makeNSViewController(context: Context) -> PersistentTwoPaneSplitViewController {
        PersistentTwoPaneSplitViewController(
            sidebar: prepared(sidebar),
            content: prepared(content)
        )
    }

    func updateNSViewController(_ controller: PersistentTwoPaneSplitViewController, context: Context) {
        controller.update(
            sidebar: prepared(sidebar),
            content: prepared(content)
        )
    }

    private func prepared<V: View>(_ view: V) -> AnyView {
        AnyView(
            view
                .modelContext(modelContext)
                .environment(\.newsprintTheme, theme)
                .environment(\.readerFontChoice, readerFontChoice)
                .environment(\.readerFontSize, readerFontSize)
                .environment(\.articleListDensity, articleListDensity)
                .preferredColorScheme(theme.colorScheme)
                .tint(theme.tint)
        )
    }
}

@MainActor
final class PersistentTwoPaneSplitViewController: NSSplitViewController {
    private let sidebarHost: NSHostingController<AnyView>
    private let contentHost: NSHostingController<AnyView>

    init(sidebar: AnyView, content: AnyView) {
        sidebarHost = NSHostingController(rootView: sidebar)
        contentHost = NSHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)

        splitView.autosaveName = "NewsprintRootTwoPaneSplitView"
        splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 320

        let contentItem = NSSplitViewItem(viewController: contentHost)
        contentItem.minimumThickness = 520

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(sidebar: AnyView, content: AnyView) {
        sidebarHost.rootView = sidebar
        contentHost.rootView = content
    }
}
