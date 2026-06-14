import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import newsprintCore

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newsprintTheme) private var theme
    @EnvironmentObject private var agentController: NewsprintAgentController
    @Query private var settingsItems: [AppSettings]
    @Query(sort: \Article.fetchedAt, order: .reverse) private var articles: [Article]
    @State private var errorMessage: String?
    @State private var isConfirmingDeleteAll = false
    @State private var showingStarredExporter = false
    @State private var starredExportDocument = TextFileDocument()

    var body: some View {
        AdminPageShell("Settings") {
            if let settings = settingsItems.first {
                settingsContent(settings)
            } else {
                ContentUnavailableView("Loading Settings", systemImage: "gearshape")
            }
        }
        .task {
            ensureSettings()
        }
        .confirmationDialog("Delete all local Newsprint data?", isPresented: $isConfirmingDeleteAll) {
            Button("Delete All Local Data", role: .destructive) {
                deleteAllLocalData()
            }
        }
        .fileExporter(
            isPresented: $showingStarredExporter,
            document: starredExportDocument,
            contentType: .markdown,
            defaultFilename: "newsprint-starred.md"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func settingsContent(_ settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection("Appearance", caption: "Tune the reading surface without changing your data.") {
                AdminFieldRow("Theme") {
                    Picker("", selection: themeBinding(for: settings)) {
                        ForEach(AppThemeChoice.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .labelsHidden()
                }

                AdminFieldRow("Menu bar icon") {
                    Picker("", selection: menuBarIconBinding) {
                        ForEach(MenuBarIconChoice.allCases, id: \.self) { icon in
                            Label(icon.displayName, systemImage: icon.systemImage)
                                .tag(icon.rawValue)
                        }
                    }
                    .labelsHidden()
                }

                AdminFieldRow("Feed font") {
                    Picker("", selection: readerFontBinding(for: settings)) {
                        ForEach(ReaderFontChoice.allCases, id: \.self) { font in
                            Text(font.displayName).tag(font)
                        }
                    }
                    .labelsHidden()
                }

                AdminFieldRow("Feed font size", caption: "\(settings.readerFontSize) pt") {
                    Stepper("", value: readerFontSizeBinding(for: settings), in: AppSettings.readerFontSizeRange)
                        .labelsHidden()
                }

                AdminFieldRow("Feed card size") {
                    Picker("", selection: densityBinding(for: settings)) {
                        ForEach(ArticleListDensity.allCases, id: \.self) { density in
                            Text(density.displayName).tag(density)
                        }
                    }
                    .labelsHidden()
                }

                AdminFieldRow("Web preview padding", caption: "\(settings.webPreviewHorizontalPadding) px") {
                    Stepper("", value: webPreviewPaddingBinding(for: settings), in: AppSettings.webPreviewHorizontalPaddingRange)
                        .labelsHidden()
                }
            }

            SettingsSection("Refresh") {
                AdminFieldRow("Background refresh", caption: "Refreshes while Newsprint stays in the menu bar.") {
                    Toggle("", isOn: refreshWhileOpenEnabledBinding(for: settings))
                        .labelsHidden()
                }

                if settings.refreshWhileOpenMinutes != nil {
                    AdminFieldRow("Refresh interval", caption: "Every \(settings.refreshWhileOpenMinutes ?? 60) minutes") {
                        Stepper("", value: refreshIntervalBinding(for: settings), in: 5...240, step: 5)
                            .labelsHidden()
                    }
                }
            }

            SettingsSection("Reading") {
                AdminFieldRow("Mark read on open", caption: "Expanding an article marks it read.") {
                    Toggle("", isOn: binding(settings, \.markReadOnOpen))
                        .labelsHidden()
                }
            }

            SettingsSection("Retention", caption: "Starred articles are never deleted automatically.") {
                AdminFieldRow("Unstarred article retention", caption: "\(settings.retentionDays) days") {
                    Stepper("", value: retentionBinding(for: settings), in: 1...365)
                        .labelsHidden()
                }

                AdminFieldRow("Last cleanup", caption: settings.lastRetentionCleanupAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never") {
                    Button("Run Cleanup", systemImage: "trash") {
                        runCleanup(settings: settings)
                    }
                }

                AdminFieldRow("Deleted in last cleanup") {
                    Text("\(settings.lastRetentionDeletedCount)")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(theme.metadata)
                }
            }

            SettingsSection("Data Ownership") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Database Location")
                        .font(.callout.weight(.medium))
                    Text(databaseLocation.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.metadata)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.readerSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
                }

                Divider()

                AdminFieldRow("Starred articles", caption: "Export saved articles as Markdown.") {
                    Button("Export", systemImage: "square.and.arrow.up") {
                        exportStarredArticles()
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            dangerZone
        }
    }

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminSectionHeader("Danger Zone", caption: "Permanent local data actions.")
            Button("Delete All Local Data", systemImage: "trash", role: .destructive) {
                isConfirmingDeleteAll = true
            }
            .buttonStyle(.bordered)
            .tint(.red.opacity(0.82))
        }
        .padding(.top, 8)
    }

    private var databaseLocation: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "newsprint/newsprint.store") ?? URL(fileURLWithPath: "~/Library/Application Support/newsprint/newsprint.store")
    }

    private var menuBarIconBinding: Binding<String> {
        Binding(
            get: { agentController.menuBarIconRawValue },
            set: { agentController.updateMenuBarIcon(rawValue: $0) }
        )
    }

    private func retentionBinding(for settings: AppSettings) -> Binding<Int> {
        Binding(
            get: { settings.retentionDays },
            set: { newValue in
                settings.retentionDays = min(max(newValue, 1), 365)
                runCleanup(settings: settings)
            }
        )
    }

    private func themeBinding(for settings: AppSettings) -> Binding<AppThemeChoice> {
        Binding(
            get: { settings.themeChoice },
            set: { value in
                settings.themeChoice = value
                saveSettings()
            }
        )
    }

    private func readerFontBinding(for settings: AppSettings) -> Binding<ReaderFontChoice> {
        Binding(
            get: { settings.readerFontChoice },
            set: { value in
                settings.readerFontChoice = value
                saveSettings()
            }
        )
    }

    private func readerFontSizeBinding(for settings: AppSettings) -> Binding<Int> {
        Binding(
            get: { settings.readerFontSize },
            set: { value in
                settings.clampReaderFontSize(value)
                saveSettings()
            }
        )
    }

    private func densityBinding(for settings: AppSettings) -> Binding<ArticleListDensity> {
        Binding(
            get: { settings.articleListDensity },
            set: { value in
                settings.articleListDensity = value
                saveSettings()
            }
        )
    }

    private func webPreviewPaddingBinding(for settings: AppSettings) -> Binding<Int> {
        Binding(
            get: { settings.webPreviewHorizontalPadding },
            set: { value in
                settings.clampWebPreviewHorizontalPadding(value)
                saveSettings()
            }
        )
    }

    private func binding<Value>(_ settings: AppSettings, _ keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                settings[keyPath: keyPath] = value
                saveSettings()
            }
        )
    }

    private func refreshWhileOpenEnabledBinding(for settings: AppSettings) -> Binding<Bool> {
        Binding(
            get: { settings.refreshWhileOpenMinutes != nil },
            set: { enabled in
                settings.refreshWhileOpenMinutes = enabled ? 60 : nil
                saveSettings()
            }
        )
    }

    private func refreshIntervalBinding(for settings: AppSettings) -> Binding<Int> {
        Binding(
            get: { settings.refreshWhileOpenMinutes ?? 60 },
            set: { value in
                settings.refreshWhileOpenMinutes = min(max(value, 5), 240)
                saveSettings()
            }
        )
    }

    private func ensureSettings() {
        do {
            _ = try SettingsRepository.loadOrCreate(in: modelContext)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runCleanup(settings: AppSettings) {
        do {
            let result = try RetentionEngine().cleanup(
                context: modelContext,
                retentionDays: settings.retentionDays
            )
            settings.lastRetentionCleanupAt = result.lastCleanupAt
            settings.lastRetentionDeletedCount = result.deletedCount
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSettings() {
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportStarredArticles() {
        starredExportDocument = TextFileDocument(text: StarredArticleExporter().markdown(for: articles))
        showingStarredExporter = true
    }

    private func deleteAllLocalData() {
        do {
            try DataOwnershipRepository.deleteAllLocalData(in: modelContext)
            _ = try SettingsRepository.loadOrCreate(in: modelContext)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder let content: Content

    init(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminSectionHeader(title, caption: caption)
            VStack(spacing: 0) {
                content
            }
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }
}
