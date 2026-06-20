import Foundation
import SwiftData
import Testing
@testable import newsprintCore

@MainActor
@Test func ruleDefinitionSnapshotsFilterRuleFields() throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let rule = FilterRule(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
        name: "Boost Swift",
        target: .title,
        matchMode: .contains,
        pattern: "swift",
        action: .boost,
        actionValue: "5",
        enabled: false,
        priority: 7,
        createdAt: createdAt
    )

    let definition = RuleDefinition(rule: rule)

    #expect(definition.id == rule.id)
    #expect(definition.target == .title)
    #expect(definition.matchMode == .contains)
    #expect(definition.pattern == "swift")
    #expect(definition.action == .boost)
    #expect(definition.actionValue == "5")
    #expect(definition.enabled == false)
    #expect(definition.priority == 7)
    #expect(definition.createdAt == createdAt)
}

@MainActor
@Test func ruleDefinitionApplicationMatchesFilterRuleApplication() throws {
    let draft = makeRuleDraft(title: "SwiftData RSS reader", contentText: "Local-first Swift app")
    let rule = FilterRule(
        name: "Tag Swift",
        target: .title,
        matchMode: .contains,
        pattern: "swift",
        action: .tag,
        actionValue: "Swift",
        priority: 1
    )

    let modelResult = RuleEngine().apply(rules: [rule], to: draft)
    let definitionResult = RuleEngine().apply(rules: [RuleDefinition(rule: rule)], to: draft)

    #expect(definitionResult == modelResult)
}

@MainActor
@Test func ruleEngineAppliesActionsInPriorityOrder() throws {
    let draft = makeRuleDraft(
        title: "SwiftData RSS reader",
        contentText: "Local-first Swift app"
    )
    let tagRule = FilterRule(
        name: "Tag Swift",
        target: .title,
        matchMode: .contains,
        pattern: "swift",
        action: .tag,
        actionValue: "Swift",
        priority: 20
    )
    let boostRule = FilterRule(
        name: "Boost local",
        target: .content,
        matchMode: .contains,
        pattern: "local-first",
        action: .boost,
        actionValue: "3.5",
        priority: 10
    )

    let result = RuleEngine().apply(rules: [tagRule, boostRule], to: draft)

    #expect(result.scoreDelta == 3.5)
    #expect(result.tags == ["Swift"])
    #expect(result.matchedRuleIDs == [boostRule.id, tagRule.id])
}

@MainActor
@Test func ruleEngineHideWinsOverBoostAndStarIsIndependent() throws {
    let draft = makeRuleDraft(title: "Launch rumor", contentText: "spoiler details")
    let hideRule = FilterRule(
        name: "Hide rumor",
        target: .title,
        matchMode: .contains,
        pattern: "rumor",
        action: .hide,
        priority: 1
    )
    let starRule = FilterRule(
        name: "Star launches",
        target: .title,
        matchMode: .contains,
        pattern: "launch",
        action: .star,
        priority: 2
    )
    let boostRule = FilterRule(
        name: "Boost spoilers",
        target: .content,
        matchMode: .contains,
        pattern: "spoiler",
        action: .boost,
        actionValue: "10",
        priority: 3
    )

    let result = RuleEngine().apply(rules: [boostRule, starRule, hideRule], to: draft)

    #expect(result.isHidden)
    #expect(result.isStarred)
    #expect(result.scoreDelta == 0)
}

@MainActor
@Test func reapplyRulesResetsRuleDerivedFieldsButPreservesManualState() throws {
    let container = try ModelContainer(
        for: Source.self, Article.self, AppSettings.self, FilterRule.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let sourceID = UUID()
    let article = Article(
        id: "article-1",
        sourceID: sourceID,
        sourceTitle: "Example",
        title: "SwiftData news",
        url: URL(string: "https://example.com/swift")!,
        contentText: "A local-first reader",
        isRead: true,
        isStarred: true,
        score: 99,
        matchedRuleIDs: ["stale"],
        tagNames: ["Old"]
    )
    let rule = FilterRule(
        name: "Tag local",
        target: .content,
        matchMode: .contains,
        pattern: "local-first",
        action: .tag,
        actionValue: "Local",
        priority: 1
    )
    context.insert(article)
    context.insert(rule)
    try context.save()

    try RuleEngine().reapply(rules: [rule], context: context)

    #expect(article.isStarred)
    #expect(article.isRead)
    #expect(article.score == 0)
    #expect(article.tagNames == ["Local"])
    #expect(article.matchedRuleIDs == [rule.id.uuidString])
}

@MainActor
@Test func articleScoreIncludesHackerNewsEngagementAndRuleBoost() throws {
    let draft = ArticleDraft(
        sourceID: UUID(),
        sourceTitle: "Hacker News Show",
        title: "Show HN: Example",
        url: URL(string: "https://example.com")!,
        author: nil,
        publishedAt: nil,
        updatedAt: nil,
        excerpt: nil,
        contentHTML: nil,
        contentText: "Article URL: https://example.com Comments URL: https://news.ycombinator.com/item?id=1 Points: 42 # Comments: 3",
        externalID: nil
    )
    let result = RuleResult(scoreDelta: 5)

    let article = Article(draft: draft, ruleResult: result)

    #expect(article.score == 50)
}

@MainActor
@Test func hiddenHackerNewsArticleScoreStaysZero() throws {
    let draft = ArticleDraft(
        sourceID: UUID(),
        sourceTitle: "Hacker News Show",
        title: "Show HN: Example",
        url: URL(string: "https://example.com")!,
        author: nil,
        publishedAt: nil,
        updatedAt: nil,
        excerpt: nil,
        contentHTML: nil,
        contentText: "Article URL: https://example.com Comments URL: https://news.ycombinator.com/item?id=1 Points: 42 # Comments: 3",
        externalID: nil
    )
    let result = RuleResult(isHidden: true, scoreDelta: 5)

    let article = Article(draft: draft, ruleResult: result)

    #expect(article.score == 0)
}

private func makeRuleDraft(title: String, contentText: String?) -> ArticleDraft {
    ArticleDraft(
        sourceID: UUID(),
        sourceTitle: "Example",
        title: title,
        url: URL(string: "https://example.com/article")!,
        author: "Author",
        publishedAt: nil,
        updatedAt: nil,
        excerpt: nil,
        contentHTML: nil,
        contentText: contentText,
        externalID: nil
    )
}
