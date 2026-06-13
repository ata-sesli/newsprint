import AppKit
import SwiftData
import SwiftUI

struct PersistentThreePaneSplitView<Sidebar: View, Content: View, Detail: View>: NSViewControllerRepresentable {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    @Environment(\.articleListDensity) private var articleListDensity
    @Binding private var isDetailCollapsed: Bool
    private let sidebar: Sidebar
    private let content: Content
    private let detail: Detail

    init(
        isDetailCollapsed: Binding<Bool>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        _isDetailCollapsed = isDetailCollapsed
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isDetailCollapsed: $isDetailCollapsed)
    }

    func makeNSViewController(context: Context) -> PersistentSplitViewController {
        let controller = PersistentSplitViewController(
            sidebar: prepared(sidebar),
            content: prepared(content),
            detail: prepared(detail),
            isDetailCollapsed: isDetailCollapsed
        )
        controller.onDetailCollapseChanged = { collapsed in
            context.coordinator.isDetailCollapsed.wrappedValue = collapsed
        }
        return controller
    }

    func updateNSViewController(_ controller: PersistentSplitViewController, context: Context) {
        controller.update(
            sidebar: prepared(sidebar),
            content: prepared(content),
            detail: prepared(detail),
            isDetailCollapsed: isDetailCollapsed
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

    final class Coordinator {
        let isDetailCollapsed: Binding<Bool>

        init(isDetailCollapsed: Binding<Bool>) {
            self.isDetailCollapsed = isDetailCollapsed
        }
    }
}

@MainActor
final class PersistentSplitViewController: NSSplitViewController {
    var onDetailCollapseChanged: ((Bool) -> Void)?

    private let sidebarHost: NSHostingController<AnyView>
    private let contentHost: NSHostingController<AnyView>
    private let detailHost: NSHostingController<AnyView>
    private let detailSplitItem: NSSplitViewItem

    init(sidebar: AnyView, content: AnyView, detail: AnyView, isDetailCollapsed: Bool) {
        sidebarHost = NSHostingController(rootView: sidebar)
        contentHost = NSHostingController(rootView: content)
        detailHost = NSHostingController(rootView: detail)
        detailSplitItem = NSSplitViewItem(viewController: detailHost)
        super.init(nibName: nil, bundle: nil)

        splitView.autosaveName = "NewsprintRootSplitView"
        splitView.dividerStyle = .thin
        splitView.delegate = self

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 320

        let contentItem = NSSplitViewItem(viewController: contentHost)
        contentItem.minimumThickness = 320

        detailSplitItem.minimumThickness = 420
        detailSplitItem.isCollapsed = isDetailCollapsed

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        addSplitViewItem(detailSplitItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(sidebar: AnyView, content: AnyView, detail: AnyView, isDetailCollapsed: Bool) {
        sidebarHost.rootView = sidebar
        contentHost.rootView = content
        detailHost.rootView = detail

        if detailSplitItem.isCollapsed != isDetailCollapsed {
            detailSplitItem.animator().isCollapsed = isDetailCollapsed
        }
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        onDetailCollapseChanged?(detailSplitItem.isCollapsed)
    }
}
