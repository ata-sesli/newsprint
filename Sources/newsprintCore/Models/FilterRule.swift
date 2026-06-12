import Foundation
import SwiftData

public enum RuleTarget: String, Codable, CaseIterable, Identifiable {
    case title
    case author
    case source
    case url
    case excerpt
    case content
    case tags

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .title: "Title"
        case .author: "Author"
        case .source: "Source"
        case .url: "URL"
        case .excerpt: "Excerpt"
        case .content: "Content"
        case .tags: "Tags"
        }
    }
}

public enum RuleMatchMode: String, Codable, CaseIterable, Identifiable {
    case contains
    case doesNotContain

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .contains: "Contains"
        case .doesNotContain: "Does Not Contain"
        }
    }
}

public enum RuleAction: String, Codable, CaseIterable, Identifiable {
    case hide
    case star
    case markRead
    case boost
    case tag

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hide: "Hide"
        case .star: "Star"
        case .markRead: "Mark Read"
        case .boost: "Boost"
        case .tag: "Tag"
        }
    }
}

@Model
public final class FilterRule {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var targetRawValue: String
    public var matchModeRawValue: String
    public var pattern: String
    public var actionRawValue: String
    public var actionValue: String?
    public var enabled: Bool
    public var priority: Int
    public var createdAt: Date
    public var updatedAt: Date

    public var target: RuleTarget {
        get { RuleTarget(rawValue: targetRawValue) ?? .title }
        set { targetRawValue = newValue.rawValue }
    }

    public var matchMode: RuleMatchMode {
        get { RuleMatchMode(rawValue: matchModeRawValue) ?? .contains }
        set { matchModeRawValue = newValue.rawValue }
    }

    public var action: RuleAction {
        get { RuleAction(rawValue: actionRawValue) ?? .tag }
        set { actionRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        target: RuleTarget,
        matchMode: RuleMatchMode,
        pattern: String,
        action: RuleAction,
        actionValue: String? = nil,
        enabled: Bool = true,
        priority: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.targetRawValue = target.rawValue
        self.matchModeRawValue = matchMode.rawValue
        self.pattern = pattern
        self.actionRawValue = action.rawValue
        self.actionValue = actionValue
        self.enabled = enabled
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

