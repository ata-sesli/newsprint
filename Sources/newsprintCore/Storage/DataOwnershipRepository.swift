import Foundation
import SwiftData

@MainActor
public enum DataOwnershipRepository {
    public static func deleteAllLocalData(in context: ModelContext) throws {
        for article in try context.fetch(FetchDescriptor<Article>()) {
            context.delete(article)
        }
        for source in try context.fetch(FetchDescriptor<Source>()) {
            context.delete(source)
        }
        for rule in try context.fetch(FetchDescriptor<FilterRule>()) {
            context.delete(rule)
        }
        for settings in try context.fetch(FetchDescriptor<AppSettings>()) {
            context.delete(settings)
        }
        try context.save()
    }
}

