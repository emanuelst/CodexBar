#if os(macOS)
import Foundation
import WebKit

/// Extracts only the billing renewal text from the authenticated Codex settings SPA.
/// The page is rendered in the existing CodexBar WebKit session; no cookies or raw
/// account payloads leave the process.
let openAIBillingScrapeScript = """
(() => {
  const bodyText = document.body ? String(document.body.innerText || '').replace(/\\s+/g, ' ').trim() : '';
  const hash = String(window.location.hash || '').toLowerCase();
  const isBillingRoute = hash.includes('settings/billing');
  const match = bodyText.match(/(?:auto[- ]?renews|renews)\\s+on\\s+([A-Za-z]+\\s+\\d{1,2},\\s+\\d{4})/i);
  return {
    isBillingRoute,
    renewalDateText: match ? String(match[1]).trim() : null
  };
})();
"""

/// Loads the billing route in the existing authenticated WebKit session, extracts the
/// renewal date, then restores the usage dashboard route.
@MainActor
enum OpenAIBilling {
    private static let billingURL = URL(string: "https://chatgpt.com/#settings/Billing")!
    private static let usageURL = URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage")!

    static func fetch(
        _ webView: WKWebView,
        deadline: Date,
        logger: @escaping (String) -> Void) async -> Date?
    {
        guard Date() < deadline else { return nil }

        _ = webView.load(OpenAIDashboardFetcher.usageURLRequest(url: self.billingURL))
        let billingDeadline = min(deadline, Date().addingTimeInterval(8))
        defer { _ = webView.load(OpenAIDashboardFetcher.usageURLRequest(url: self.usageURL)) }

        while Date() < billingDeadline {
            try? await Task.sleep(for: .milliseconds(400))
            guard let any = try? await webView.evaluateJavaScript(openAIBillingScrapeScript),
                  let dict = any as? [String: Any],
                  (dict["isBillingRoute"] as? Bool) == true
            else { continue }

            guard let text = dict["renewalDateText"] as? String,
                  let date = OpenAIBillingDateParser.parse(text)
            else { continue }

            logger("billing renewal date found")
            return date
        }

        logger("billing renewal date not found")
        return nil
    }
}

/// The billing page currently presents a date-only English label, e.g. "Aug 20, 2026".
/// Keep parsing isolated so the UI wording can evolve without touching the WebKit flow.
enum OpenAIBillingDateParser {
    static func parse(_ text: String, locale: Locale = .current) -> Date? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\u{00a0}", with: " ")
        guard !normalized.isEmpty else { return nil }

        for candidateLocale in [locale, Locale(identifier: "en_US_POSIX")] {
            for format in ["MMM d, yyyy", "MMMM d, yyyy"] {
                let formatter = DateFormatter()
                formatter.locale = candidateLocale
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = TimeZone.current
                formatter.dateFormat = format
                if let date = formatter.date(from: normalized) { return date }
            }
        }
        return nil
    }
}
#endif
