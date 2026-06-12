import SwiftData
import SwiftUI
import newsprintCore

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let settings = settingsItems.first {
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
}

