import Foundation
import SwiftData

public struct RuleResult: Sendable, Equatable {
    public var isHidden: Bool
    public var isStarred: Bool
    public var isRead: Bool
    public var scoreDelta: Double
    public var tags: [String]
    public var matchedRuleIDs: [UUID]

    public init(
        isHidden: Bool = false,
        isStarred: Bool = false,
        isRead: Bool = false,
        scoreDelta: Double = 0,
        tags: [String] = [],
        matchedRuleIDs: [UUID] = []
    ) {
        self.isHidden = isHidden
        self.isStarred = isStarred
        self.isRead = isRead
        self.scoreDelta = scoreDelta
        self.tags = tags
        self.matchedRuleIDs = matchedRuleIDs
    }
}

public struct RuleDefinition: Sendable, Equatable {
    public let id: UUID
    public let target: RuleTarget
    public let matchMode: RuleMatchMode
    public let pattern: String
    public let action: RuleAction
    public let actionValue: String?
    public let enabled: Bool
    public let priority: Int
    public let createdAt: Date

    public init(
        id: UUID,
        target: RuleTarget,
        matchMode: RuleMatchMode,
        pattern: String,
        action: RuleAction,
        actionValue: String?,
        enabled: Bool,
        priority: Int,
        createdAt: Date
    ) {
        self.id = id
        self.target = target
        self.matchMode = matchMode
        self.pattern = pattern
        self.action = action
        self.actionValue = actionValue
        self.enabled = enabled
        self.priority = priority
        self.createdAt = createdAt
    }
}

public struct RuleEngine {
    public init() {}

    public func apply(rules: [RuleDefinition], to draft: ArticleDraft) -> RuleResult {
        var result = RuleResult()

        for rule in rules.sorted(by: ruleSort).filter(\.enabled) {
            guard matches(rule: rule, draft: draft, existingTags: result.tags) else {
                continue
            }

            result.matchedRuleIDs.append(rule.id)
            switch rule.action {
            case .hide:
                result.isHidden = true
                result.scoreDelta = 0
            case .star:
                result.isStarred = true
            case .markRead:
                result.isRead = true
            case .boost:
                if !result.isHidden {
                    result.scoreDelta += Double(rule.actionValue ?? "") ?? 1
                }
            case .tag:
                if let tag = rule.actionValue?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty, !result.tags.contains(tag) {
                    result.tags.append(tag)
                }
            }
        }

        if result.isHidden {
            result.scoreDelta = 0
        }
        return result
    }

    @MainActor
    public func apply(rules: [FilterRule], to draft: ArticleDraft) -> RuleResult {
        apply(rules: rules.map(RuleDefinition.init(rule:)), to: draft)
    }

    @MainActor
    public func reapply(rules: [FilterRule], context: ModelContext) throws {
        let definitions = rules.map(RuleDefinition.init(rule:))
        let articles = try context.fetch(FetchDescriptor<Article>())
        for article in articles {
            let result = apply(rules: definitions, to: ArticleDraft(article: article))
            let engagementScore = HackerNewsMetadata(text: article.contentText ?? article.excerpt)?.engagementScore ?? 0
            article.score = result.isHidden ? 0 : engagementScore + result.scoreDelta
            article.tagNames = result.tags
            article.matchedRuleIDs = result.matchedRuleIDs.map(\.uuidString)
            article.isHidden = article.isHidden || result.isHidden
            article.isStarred = article.isStarred || result.isStarred
            article.isRead = article.isRead || result.isRead
        }
        try context.save()
    }

    private func matches(rule: RuleDefinition, draft: ArticleDraft, existingTags: [String]) -> Bool {
        let targetText = text(for: rule.target, in: draft, existingTags: existingTags).lowercased()
        let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !pattern.isEmpty else { return false }

        switch rule.matchMode {
        case .contains:
            return targetText.contains(pattern)
        case .doesNotContain:
            return !targetText.contains(pattern)
        }
    }

    private func text(for target: RuleTarget, in draft: ArticleDraft, existingTags: [String]) -> String {
        switch target {
        case .title:
            draft.title
        case .author:
            draft.author ?? ""
        case .source:
            draft.sourceTitle
        case .url:
            draft.url.absoluteString
        case .excerpt:
            draft.excerpt ?? ""
        case .content:
            [draft.contentText, draft.excerpt, HTMLTextExtractor.text(fromHTML: draft.contentHTML)]
                .compactMap { $0 }
                .joined(separator: " ")
        case .tags:
            existingTags.joined(separator: " ")
        }
    }

    private func ruleSort(_ lhs: RuleDefinition, _ rhs: RuleDefinition) -> Bool {
        if lhs.priority == rhs.priority {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.priority < rhs.priority
    }
}

public extension RuleDefinition {
    init(rule: FilterRule) {
        self.init(
            id: rule.id,
            target: rule.target,
            matchMode: rule.matchMode,
            pattern: rule.pattern,
            action: rule.action,
            actionValue: rule.actionValue,
            enabled: rule.enabled,
            priority: rule.priority,
            createdAt: rule.createdAt
        )
    }
}

private extension ArticleDraft {
    init(article: Article) {
        self.init(
            sourceID: article.sourceID,
            sourceTitle: article.sourceTitle,
            title: article.title,
            url: article.url,
            author: article.author,
            publishedAt: article.publishedAt,
            updatedAt: article.updatedAt,
            excerpt: article.excerpt,
            contentHTML: article.contentHTML,
            contentText: article.contentText,
            externalID: article.id
        )
    }
}
