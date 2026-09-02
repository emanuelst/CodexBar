import CodexBarCore
import Foundation

extension UsageStore {
    /// Attaches metadata from a dashboard that has already passed the Codex authority check.
    @discardableResult
    func applyOpenAIDashboardSubscriptionMetadata(
        _ dashboard: OpenAIDashboardSnapshot) -> Bool
    {
        // Provider-specific by design: authorized OpenAI dashboard metadata attaches only to the active Codex snapshot.
        guard let currentUsage = self.snapshots[.codex] else { return false }

        let updatedUsage = currentUsage.withSubscriptionMetadata(
            expiresAt: dashboard.subscriptionExpiresAt,
            renewsAt: dashboard.subscriptionRenewsAt)
        self.snapshots[.codex] = updatedUsage
        let didChange = updatedUsage.subscriptionExpiresAt != currentUsage.subscriptionExpiresAt ||
            updatedUsage.subscriptionRenewsAt != currentUsage.subscriptionRenewsAt
        if didChange {
            self.persistWidgetSnapshot(reason: "dashboard-subscription-metadata")
        }
        return didChange
    }
}
