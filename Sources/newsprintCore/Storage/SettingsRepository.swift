import Foundation
import SwiftData

@MainActor
public enum SettingsRepository {
    public static func loadOrCreate(in context: ModelContext) throws -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }
}

