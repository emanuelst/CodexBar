import Foundation
import Testing
@testable import CodexBarCore

struct CodexBarConfigCompatibilityTests {
    @Test
    func `legacy config without new optional fields still decodes`() throws {
        let legacy = Data(#"{"version":1,"providers":[{"id":"codex","enabled":true,"apiKey":"preserved-key"}]}"#.utf8)

        let config = try CodexBarConfig.decode(from: legacy)

        #expect(config.providerConfig(for: .codex)?.apiKey == "preserved-key")
        #expect(config.providerConfig(for: .codex)?.hiddenUsageItemIDs == nil)
    }
}
