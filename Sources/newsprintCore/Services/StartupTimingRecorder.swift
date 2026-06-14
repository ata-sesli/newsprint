import Foundation

public struct StartupTimingEvent: Equatable, Sendable {
    public let name: String
    public let elapsedMilliseconds: Double

    public init(name: String, elapsedMilliseconds: Double) {
        self.name = name
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

public final class StartupTimingRecorder {
    public private(set) var events: [StartupTimingEvent] = []

    private let start: Date
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
        start = now()
    }

    @discardableResult
    public func mark(_ name: String) -> StartupTimingEvent {
        let event = StartupTimingEvent(
            name: name,
            elapsedMilliseconds: now().timeIntervalSince(start) * 1000
        )
        events.append(event)
        return event
    }

    @discardableResult
    public func markAndLog(_ name: String) -> StartupTimingEvent {
        let event = mark(name)
        NewsprintLog.startup.info("\(event.name, privacy: .public) \(event.elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)ms")
        return event
    }
}
