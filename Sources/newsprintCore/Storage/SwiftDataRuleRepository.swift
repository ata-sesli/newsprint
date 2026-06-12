import Foundation
import SwiftData

@MainActor
public final class SwiftDataRuleRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func enabledRules() throws -> [FilterRule] {
        let descriptor = FetchDescriptor<FilterRule>(
            predicate: #Predicate<FilterRule> { rule in
                rule.enabled
            },
            sortBy: [SortDescriptor(\FilterRule.priority), SortDescriptor(\FilterRule.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    public func allRules() throws -> [FilterRule] {
        let descriptor = FetchDescriptor<FilterRule>(
            sortBy: [SortDescriptor(\FilterRule.priority), SortDescriptor(\FilterRule.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    public func save(_ rule: FilterRule) throws {
        rule.updatedAt = Date()
        context.insert(rule)
        try context.save()
    }

    public func delete(_ rule: FilterRule) throws {
        context.delete(rule)
        try context.save()
    }

    public func reapplyEnabledRules() throws {
        try RuleEngine().reapply(rules: enabledRules(), context: context)
    }
}

