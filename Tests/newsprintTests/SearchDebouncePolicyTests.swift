import Testing
@testable import newsprintCore

@Test func searchDebouncePolicyUsesOneHundredMillisecondDelay() {
    #expect(SearchDebouncePolicy.delayNanoseconds == 100_000_000)
}

@Test func searchDebouncePolicyTrimsWhitespaceBeforeApplyingSearch() {
    #expect(SearchDebouncePolicy.normalized("  swift data \n") == "swift data")
}
