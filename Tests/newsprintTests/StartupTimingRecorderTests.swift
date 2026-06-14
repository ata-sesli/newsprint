import Foundation
import Testing
@testable import newsprintCore

@Suite("Startup timing recorder")
struct StartupTimingRecorderTests {
    @Test("records elapsed milliseconds for marked events")
    func recordsElapsedMilliseconds() {
        var dates = [
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 10.125),
            Date(timeIntervalSince1970: 10.5)
        ]
        let recorder = StartupTimingRecorder(now: { dates.removeFirst() })

        let first = recorder.mark("model container")
        let second = recorder.mark("first feed page")

        #expect(first.name == "model container")
        #expect(first.elapsedMilliseconds == 125)
        #expect(second.name == "first feed page")
        #expect(second.elapsedMilliseconds == 500)
        #expect(recorder.events.map(\.name) == ["model container", "first feed page"])
    }
}
