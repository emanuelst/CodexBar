import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// Behavioral regressions reproduced on reviewed candidate c0afdd03.
@Suite(.serialized, CodexCredentialFixtures())
@MainActor
struct CurrentReviewRegressionTests {
    @Test
    func `mixed monthly catalogue semantics are independent of account order`() async throws {
        try await CodexAccountScopedRefreshTests()
            .withSelectedAccountRetentionFixture(sameEmail: false) { store, _, _ in
                store.settings.showOptionalCreditsAndExtraUsage = false
                let now = Date()
                store.codexAccountSnapshots = store.codexAccountSnapshots.enumerated().map { index, record in
                    CodexAccountUsageSnapshot(
                        account: record.account,
                        snapshot: UsageSnapshot(
                            primary: index == 0 ? RateWindow(
                                usedPercent: 24, windowMinutes: 43200, resetsAt: nil, resetDescription: nil) : nil,
                            secondary: nil,
                            updatedAt: now),
                        error: nil,
                        sourceLabel: "synthetic",
                        credits: index == 0 ? nil : CreditsSnapshot(
                            remaining: 73,
                            events: [],
                            updatedAt: now,
                            codexCreditLimit: CodexCreditLimitSnapshot(
                                used: 27, limit: 100, remainingPercent: 73, resetsAt: nil, updatedAt: now)))
                }
                let overview = try #require(store.codexAccountUsageOverview(onRefresh: { _ in }))
                var expectedTitle: String?
                for rows in [overview.rows, Array(overview.rows.reversed())] {
                    let reordered = ProviderAccountUsageOverview(
                        rows: rows,
                        refreshLimit: overview.refreshLimit,
                        canRefresh: overview.canRefresh,
                        onRefresh: overview.onRefresh)
                    let monthly = reordered.usageItems.filter { $0.id == .metric("monthly") }
                    #expect(monthly.count == 1)
                    #expect(monthly.first?.requiresOptionalUsage == false)
                    #expect(monthly.first?.hasMixedOptionalUsage == true)
                    #expect(monthly.first?.title == L("Monthly"))
                    if let expectedTitle {
                        #expect(monthly.first?.title == expectedTitle)
                    } else {
                        expectedTitle = monthly.first?.title
                    }
                    let realQuota = try #require(rows.flatMap(\.usageItems).first {
                        $0.id == .metric("monthly") && !$0.requiresOptionalUsage
                    })
                    let withLiveCatalogue = ProviderUsageItemDescriptor.merging(reordered.usageItems + [realQuota])
                    #expect(withLiveCatalogue.first { $0.id == .metric("monthly") } == monthly.first)
                }
            }
    }
}
