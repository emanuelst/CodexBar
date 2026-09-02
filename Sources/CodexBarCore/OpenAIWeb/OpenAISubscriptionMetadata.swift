#if os(macOS)
import Foundation
import WebKit

/// Captures only the renewal fields from ChatGPT's own subscription request.
/// The response remains in the authenticated page; no cookies, IDs, or raw payloads
/// are passed back to CodexBar.
let openAISubscriptionCaptureScript = """
(() => {
  if (window.__codexbarSubscriptionCaptureInstalled) return;
  window.__codexbarSubscriptionCaptureInstalled = true;
  window.__codexbarSubscriptionCaptureGeneration = 0;
  window.__codexbarSubscriptionResponseStatus = null;
  window.__codexbarSubscriptionResponseSettled = false;
  window.__codexbarSubscriptionMetadata = null;
  window.__codexbarSubscriptionMetadataParseState = null;
  const originalFetch = window.fetch.bind(window);
  window.fetch = async (...args) => {
    const generation = window.__codexbarSubscriptionCaptureGeneration;
    const response = await originalFetch(...args);
    try {
      const input = args[0];
      const rawURL = input && input.url ? input.url : input;
      const requestURL = new URL(String(rawURL), window.location.href);
      if (requestURL.origin === window.location.origin &&
          requestURL.pathname === '/backend-api/subscriptions') {
        if (window.__codexbarSubscriptionCaptureGeneration === generation) {
          window.__codexbarSubscriptionResponseStatus = response.status;
          window.__codexbarSubscriptionResponseSettled = false;
        }
        response.clone().json().then(payload => {
          if (window.__codexbarSubscriptionCaptureGeneration !== generation) return;
          window.__codexbarSubscriptionResponseSettled = true;
          const hasActiveUntil = payload &&
            (Object.prototype.hasOwnProperty.call(payload, 'active_until') ||
             Object.prototype.hasOwnProperty.call(payload, 'activeUntil'));
          const hasWillRenew = payload &&
            (Object.prototype.hasOwnProperty.call(payload, 'will_renew') ||
             Object.prototype.hasOwnProperty.call(payload, 'willRenew'));
          const activeUntil = Object.prototype.hasOwnProperty.call(payload || {}, 'active_until')
            ? payload.active_until
            : payload?.activeUntil;
          const willRenew = Object.prototype.hasOwnProperty.call(payload || {}, 'will_renew')
            ? payload.will_renew
            : payload?.willRenew;
          const schemaValid = hasActiveUntil && hasWillRenew &&
            (activeUntil === null || typeof activeUntil === 'string') &&
            (willRenew === null || typeof willRenew === 'boolean');
          window.__codexbarSubscriptionMetadataParseState = schemaValid ? 'valid' : 'invalid';
          window.__codexbarSubscriptionMetadata = schemaValid ? {
            activeUntil,
            willRenew
          } : null;
        }).catch(() => {
          if (window.__codexbarSubscriptionCaptureGeneration !== generation) return;
          window.__codexbarSubscriptionResponseSettled = true;
          window.__codexbarSubscriptionMetadataParseState = 'invalid';
          window.__codexbarSubscriptionMetadata = null;
        });
      }
    } catch (_) {}
    return response;
  };
})();
"""

let openAISubscriptionResetScript = """
(() => {
  const generation = Number(window.__codexbarSubscriptionCaptureGeneration || 0) + 1;
  window.__codexbarSubscriptionCaptureGeneration = generation;
  window.__codexbarSubscriptionResponseStatus = null;
  window.__codexbarSubscriptionResponseSettled = false;
  window.__codexbarSubscriptionMetadata = null;
  window.__codexbarSubscriptionMetadataParseState = null;
  return generation;
})();
"""

let openAISubscriptionReadScript = """
(() => ({
  isBillingRoute: String(window.location.hash || '').toLowerCase().includes('settings/billing'),
  responseStatus: window.__codexbarSubscriptionResponseStatus,
  responseSettled: window.__codexbarSubscriptionResponseSettled,
  metadataParseState: window.__codexbarSubscriptionMetadataParseState,
  metadata: window.__codexbarSubscriptionMetadata || null
}))();
"""

/// Opens ChatGPT's billing settings so its frontend performs the authenticated
/// subscription request captured by `openAISubscriptionCaptureScript`.
@MainActor
enum OpenAISubscription {
    private static let billingURL = URL(string: "https://chatgpt.com/#settings/Billing")!
    private static let usageURL = URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage")!

    static func fetch(
        _ webView: WKWebView,
        deadline: Date,
        logger: @escaping (String) -> Void) async throws -> OpenAISubscriptionFetchResult
    {
        guard Date() < deadline else { return .unavailable }
        try Task.checkCancellation()

        guard await (try? webView.evaluateJavaScript(openAISubscriptionResetScript)) != nil else {
            logger("subscription metadata reset unavailable")
            return .unavailable
        }
        try Task.checkCancellation()

        _ = webView.load(OpenAIDashboardFetcher.usageURLRequest(url: self.billingURL))
        let billingDeadline = min(deadline, Date().addingTimeInterval(8))
        defer { _ = webView.load(OpenAIDashboardFetcher.usageURLRequest(url: self.usageURL)) }

        while Date() < billingDeadline {
            try await Task.sleep(for: .milliseconds(400))
            try Task.checkCancellation()
            guard let any = try? await webView.evaluateJavaScript(openAISubscriptionReadScript),
                  let result = any as? [String: Any],
                  (result["isBillingRoute"] as? Bool) == true,
                  (result["responseSettled"] as? Bool) == true
            else { continue }

            guard let status = result["responseStatus"] as? Int, (200..<300).contains(status) else {
                logger("subscription metadata unavailable")
                return .unavailable
            }

            guard (result["metadataParseState"] as? String) == "valid" else {
                logger("subscription metadata response invalid")
                return .unavailable
            }

            let raw = result["metadata"] as? [String: Any]
            let parsed = OpenAISubscriptionMetadata.parseResult(
                activeUntil: raw?["activeUntil"] as? String,
                willRenew: raw?["willRenew"] as? Bool,
                fieldsPresent: raw != nil)

            if case let .success(metadata) = parsed, let metadata {
                logger(
                    "subscription metadata found " +
                        "renewal=\(metadata.renewsAt == nil ? "0" : "1") " +
                        "expiration=\(metadata.expiresAt == nil ? "0" : "1")")
            } else if case .success = parsed {
                logger("subscription metadata response empty")
            } else {
                logger("subscription metadata response invalid")
            }
            return parsed
        }

        logger("subscription metadata unavailable")
        return .unavailable
    }
}
#endif
