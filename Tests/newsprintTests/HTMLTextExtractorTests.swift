import Testing
@testable import newsprintCore

@Test func htmlExtractorStripsTagsEntitiesAndNormalizesWhitespace() {
    let html = "<article><h1>Hello&nbsp;World</h1><p>Swift &amp; feeds<br>now</p></article>"

    let text = HTMLTextExtractor.text(fromHTML: html)

    #expect(text == "Hello World Swift & feeds now")
}

