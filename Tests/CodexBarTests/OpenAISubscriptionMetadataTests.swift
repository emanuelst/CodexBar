import XCTest
@testable import CodexBarCore

#if os(macOS)
final class OpenAISubscriptionMetadataTests: XCTestCase {
    func test_mapsRenewingSubscriptionToRenewalDate() throws {
        let metadata = try XCTUnwrap(OpenAISubscriptionMetadata.parse(
            activeUntil: "2026-08-20T14:30:07Z",
            willRenew: true))

        XCTAssertNil(metadata.expiresAt)
        XCTAssertEqual(metadata.renewsAt, ISO8601DateFormatter().date(from: "2026-08-20T14:30:07Z"))
    }

    func test_mapsNonRenewingSubscriptionToExpirationDate() throws {
        let metadata = try XCTUnwrap(OpenAISubscriptionMetadata.parse(
            activeUntil: "2026-08-20T14:30:07Z",
            willRenew: false))

        XCTAssertEqual(metadata.expiresAt, ISO8601DateFormatter().date(from: "2026-08-20T14:30:07Z"))
        XCTAssertNil(metadata.renewsAt)
    }

    func test_rejectsMissingOrMalformedMetadata() {
        XCTAssertNil(OpenAISubscriptionMetadata.parse(activeUntil: nil, willRenew: true))
        XCTAssertNil(OpenAISubscriptionMetadata.parse(activeUntil: "not a date", willRenew: true))
        XCTAssertNil(OpenAISubscriptionMetadata.parse(activeUntil: "2026-08-20T14:30:07Z", willRenew: nil))
    }
}
#endif
