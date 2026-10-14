import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// These tests also compile against upstream 46fc250d0 without changes to production code.
/// They are behavioral regression evidence, not packaged-app or interactive UI proof.
@Suite(.serialized, CodexCredentialFixtures())
@MainActor
struct UpstreamBaseRegressionTests {
    @Test
    func `startup corrupt config survives migration and an attempted provider edit`() throws {
        let configStore = testConfigStore(suiteName: "UpstreamBaseRegressionTests-startup")
        try FileManager.default.createDirectory(
            at: configStore.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("unreadable-synthetic-config".utf8)
        try corrupt.write(to: configStore.fileURL)
        let settings = SettingsStore(
            userDefaults: InMemoryUserDefaults(),
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore(),
            keychainAccessPolicy: .init(setDisabled: { _ in }, isExplicitlyDisabled: { true }),
            performInitialProviderDetection: false)
        defer { settings.configFileWatcher?.stop() }
        #expect(try Data(contentsOf: configStore.fileURL) == corrupt)

        settings.updateProviderConfig(provider: .claude) { $0.enabled = true }

        #expect(try Data(contentsOf: configStore.fileURL) == corrupt)
    }

    @Test
    func `runtime corrupt config survives an attempted provider edit`() throws {
        let settings = testSettingsStore(
            suiteName: "UpstreamBaseRegressionTests-corrupt",
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled(),
            keychainAccessPolicy: .init(setDisabled: { _ in }, isExplicitlyDisabled: { true }))
        defer { settings.configFileWatcher?.stop() }
        let corrupt = Data("unreadable-synthetic-config".utf8)
        try corrupt.write(to: settings.configStore.fileURL)
        settings.reloadConfig(reason: "regression")

        settings.updateProviderConfig(provider: .claude) { $0.enabled = true }

        #expect(try Data(contentsOf: settings.configStore.fileURL) == corrupt)
    }

    @Test
    func `real monthly quota remains independently available with optional usage off`() throws {
        let settings = testSettingsStore(
            suiteName: "UpstreamBaseRegressionTests-monthly",
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled())
        settings.showOptionalCreditsAndExtraUsage = false
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        defer {
            settings.configFileWatcher?.stop()
            store.stopSharedSpendDashboardPublication()
        }
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 27, windowMinutes: 43200, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        let model = UsageMenuCardView.Model.make(store.menuCardInput(
            for: .codex, context: .settingsAccount(.init(snapshot: snapshot))))

        #expect(model.metrics.contains { $0.id == "monthly" })
        let monthly = try #require(model.usageItemDescriptors.first { $0.id == .metric("monthly") })
        #expect(!monthly.requiresOptionalUsage)
    }

    @Test
    func `two managed accounts retain their credit catalogue while previews hide credits`() async throws {
        try await CodexAccountScopedRefreshTests()
            .withSelectedAccountRetentionFixture(sameEmail: false) { store, _, _ in
                store.settings.showOptionalCreditsAndExtraUsage = false
                let now = Date()
                store.codexAccountSnapshots = store.codexAccountSnapshots.map { record in
                    CodexAccountUsageSnapshot(
                        account: record.account,
                        snapshot: UsageSnapshot(primary: nil, secondary: nil, updatedAt: now),
                        error: nil,
                        sourceLabel: "synthetic",
                        credits: CreditsSnapshot(
                            remaining: 73,
                            events: [],
                            updatedAt: now,
                            codexCreditLimit: CodexCreditLimitSnapshot(
                                used: 27, limit: 100, remainingPercent: 73, resetsAt: nil, updatedAt: now)))
                }

                let overview = try #require(store.codexAccountUsageOverview(onRefresh: { _ in }))
                #expect(overview.rows.count == 2)
                #expect(overview.rows.allSatisfy { !$0.model.metrics.contains { $0.id == "monthly" } })
                #expect(overview.usageItems.contains { $0.id == .metric("monthly") && $0.requiresOptionalUsage })
            }
    }
}
