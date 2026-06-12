import Foundation
import SwiftData
import Testing
@testable import newsprintCore

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
