import XCTest
@testable import CodexBarCore

#if os(macOS)
final class OpenAIBillingDateParserTests: XCTestCase {
    func test_parsesScreenshotDate() throws {
        let date = OpenAIBillingDateParser.parse("Aug 20, 2026", locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertNotNil(date)
        XCTAssertEqual(try Calendar(identifier: .gregorian).component(.year, from: XCTUnwrap(date)), 2026)
        XCTAssertEqual(try Calendar(identifier: .gregorian).component(.month, from: XCTUnwrap(date)), 8)
        XCTAssertEqual(try Calendar(identifier: .gregorian).component(.day, from: XCTUnwrap(date)), 20)
    }

    func test_rejectsMalformedDate() {
        XCTAssertNil(OpenAIBillingDateParser.parse("not a date", locale: Locale(identifier: "en_US_POSIX")))
    }
}
#endif
