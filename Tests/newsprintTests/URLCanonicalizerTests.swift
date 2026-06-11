import Testing
import Foundation
@testable import newsprintCore

@Test func canonicalizerRemovesTrackingParametersAndKeepsContentParameters() throws {
    let url = try #require(URL(string: "https://example.com/read?id=42&utm_source=newsletter&gclid=abc&view=full#comments"))

    let canonical = URLCanonicalizer.canonicalize(url)

    #expect(canonical.absoluteString == "https://example.com/read?id=42&view=full#comments")
}

