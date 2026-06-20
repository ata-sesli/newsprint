import Foundation

public struct TopCandidateBuffer<Element> {
    private let limit: Int
    private let areInPreferredOrder: (Element, Element) -> Bool
    private var storage: [Element] = []

    public var items: [Element] { storage }

    public init(
        limit: Int,
        areInPreferredOrder: @escaping (Element, Element) -> Bool
    ) {
        self.limit = max(0, limit)
        self.areInPreferredOrder = areInPreferredOrder
    }

    public mutating func insert(_ element: Element) {
        guard limit > 0 else { return }
        storage.append(element)
        storage.sort(by: areInPreferredOrder)
        if storage.count > limit {
            storage.removeLast(storage.count - limit)
        }
    }

    public mutating func insert(contentsOf elements: some Sequence<Element>) {
        for element in elements {
            insert(element)
        }
    }
}
