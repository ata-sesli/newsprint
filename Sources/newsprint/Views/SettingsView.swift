import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import newsprintCore

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]
    @Query(sort: \Article.fetchedAt, order: .reverse) private var articles: [Article]
    @State private var errorMessage: String?
    @State private var isConfirmingDeleteAll = false
    @State private var showingStarredExporter = false
    @State private var starredExportDocument = TextFileDocument()

    var body: some View {
        Form {
            if let settings = settingsItems.first {
                Section("Appearance") {
                    Picker("Theme", selection: themeBinding(for: settings)) {
                        ForEach(AppThemeChoice.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }

                    Picker("Reader font", selection: readerFontBinding(for: settings)) {
                        ForEach(ReaderFontChoice.allCases, id: \.self) { font in
                            Text(font.displayName).tag(font)
                        }
                    }

                    Stepper(
                        "Reader font size: \(settings.readerFontSize)",
                        value: readerFontSizeBinding(for: settings),
                        in: AppSettings.readerFontSizeRange
                    )

                    Picker("Article list density", selection: densityBinding(for: settings)) {
                        ForEach(ArticleListDensity.allCases, id: \.self) { density in
                            Text(density.displayName).tag(density)
                        }
                    }
                }

                Section("Refresh") {
                    Toggle("Refresh on launch", isOn: binding(settings, \.refreshOnLaunch))
                    Toggle("Refresh after manual command", isOn: binding(settings, \.refreshOnManualCommand))
                    Toggle("Refresh while app is open", isOn: refreshWhileOpenEnabledBinding(for: settings))
                    if settings.refreshWhileOpenMinutes != nil {
                        Stepper(
                            "Every \(settings.refreshWhileOpenMinutes ?? 30) minutes",
                            value: refreshIntervalBinding(for: settings),
                            in: 5...240,
                            step: 5
                        )
                    }
                }

                Section("Reading") {
                    Toggle("Open links in default browser", isOn: binding(settings, \.openLinksInDefaultBrowser))
                    Toggle("Mark read on open", isOn: binding(settings, \.markReadOnOpen))
                }

                Section("Retention") {
                    Stepper(
                        "Keep unstarred articles for \(settings.retentionDays) days",
                        value: retentionBinding(for: settings),
                        in: 1...365
                    )

                    Text("Starred articles are never deleted automatically.")
                        .foregroundStyle(.secondary)

                    Text("Last cleanup: \(settings.lastRetentionCleanupAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")")
                    Text("Deleted in last cleanup: \(settings.lastRetentionDeletedCount)")

                    Button("Run Cleanup Now", systemImage: "trash") {
                        runCleanup(settings: settings)
                    }
                }

                Section("Data Ownership") {
                    Text(databaseLocation.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button("Export Starred Articles", systemImage: "square.and.arrow.up") {
                        exportStarredArticles()
                    }

                    Button("Delete All Local Data", systemImage: "trash", role: .destructive) {
                        isConfirmingDeleteAll = true
                    }
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                ContentUnavailableView("Loading Settings", systemImage: "gearshape")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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

    private var databaseLocation: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "newsprint/newsprint.store") ?? URL(fileURLWithPath: "~/Library/Application Support/newsprint/newsprint.store")
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
                settings.refreshWhileOpenMinutes = enabled ? 30 : nil
                saveSettings()
            }
        )
    }

    private func refreshIntervalBinding(for settings: AppSettings) -> Binding<Int> {
        Binding(
            get: { settings.refreshWhileOpenMinutes ?? 30 },
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
