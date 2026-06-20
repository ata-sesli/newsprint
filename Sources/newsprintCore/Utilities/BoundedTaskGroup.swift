import Foundation

public enum BoundedTaskGroup {
    public static func map<Element: Sendable, Output: Sendable>(
        _ elements: [Element],
        limit: Int,
        operation: @Sendable @escaping (Element) async -> Output
    ) async -> [Output] {
        await withTaskGroup(of: (Int, Output).self) { group in
            let taskLimit = min(max(limit, 1), elements.count)
            guard taskLimit > 0 else {
                return []
            }

            var nextIndex = 0
            for _ in 0..<taskLimit {
                let index = nextIndex
                nextIndex += 1
                group.addTask {
                    (index, await operation(elements[index]))
                }
            }

            var indexedResults: [(Int, Output)] = []
            while let result = await group.next() {
                indexedResults.append(result)
                if nextIndex < elements.count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        (index, await operation(elements[index]))
                    }
                }
            }

            return indexedResults
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }

    public static func throwingMap<Element: Sendable, Output: Sendable>(
        _ elements: [Element],
        limit: Int,
        operation: @Sendable @escaping (Element) async throws -> Output
    ) async throws -> [Output] {
        try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            let taskLimit = min(max(limit, 1), elements.count)
            guard taskLimit > 0 else {
                return []
            }

            var nextIndex = 0
            for _ in 0..<taskLimit {
                let index = nextIndex
                nextIndex += 1
                group.addTask {
                    (index, try await operation(elements[index]))
                }
            }

            var indexedResults: [(Int, Output)] = []
            while let result = try await group.next() {
                indexedResults.append(result)
                if nextIndex < elements.count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        (index, try await operation(elements[index]))
                    }
                }
            }

            return indexedResults
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }
}
