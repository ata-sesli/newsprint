import Foundation
import SwiftData
import newsprintCore

enum ArticleStateMutation {
    case toggleRead
    case toggleStar
    case toggleHidden
    case markRead

    @MainActor
    func apply(to article: Article, repository: SwiftDataArticleRepository) throws {
        switch self {
        case .toggleRead:
            try repository.markRead(article, read: !article.isRead)
        case .toggleStar:
            try repository.star(article, starred: !article.isStarred)
        case .toggleHidden:
            try repository.hide(article, hidden: !article.isHidden)
        case .markRead:
            try repository.markRead(article, read: true)
        }
    }
}

struct ArticleStateSnapshot {
    let isRead: Bool
    let isStarred: Bool
    let isHidden: Bool

    init(article: Article) {
        isRead = article.isRead
        isStarred = article.isStarred
        isHidden = article.isHidden
    }

    func restore(_ article: Article) {
        article.isRead = isRead
        article.isStarred = isStarred
        article.isHidden = isHidden
    }
}
