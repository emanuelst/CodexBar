# Usage visibility proof

Base: upstream `791c9e9137366ab841977be1dea4dc14b7a6c95b`.

## Before / after

Previously, disabling the global optional-usage setting removed Claude saved reset credits,
cloud credits, and Extra usage. The plan date appeared after resets when resets were present,
then moved under Weekly when they disappeared.

The global switch is retained with its existing storage key. Claude reset credits are now
independent, matching Codex. Codex and Claude plan dates stay directly under their quota rows.
Separate provider choices hide Claude resets, Claude Extra usage, and Codex/Claude plan dates.
The optional-usage gate still controls Cloud credits and Extra usage. Settings retain their
checkboxes and explain the gate instead of silently losing those choices.

## Visual evidence

These are native SwiftUI/AppKit renders from the freshly built test bundle, not mock HTML,
production account captures, or a live browser probe. All values and the email are synthetic.
The proof fixture supplies the global on/off model states; the production Model.make reset
policy is separately exercised by ClaudeRateLimitResetCreditsTests.

- `claude-global-on.png`: plan date below quotas, then resets, Cloud credits and Extra usage.
- `claude-global-off.png`: plan date and resets remain; gated items have explanations in Settings.

## Reproduce

```sh
make test-fast FILTER='ProviderUsageItemVisibilityTests|ClaudeRateLimitResetCreditsTests|MenuCardModelTests'
CODEXBAR_VISIBILITY_PROOF_DIR=/tmp/codexbar-visibility-proof make test-fast FILTER=ProviderUsageItemVisibilityTests
make check
make test
```

The repository runner suppresses test Keychain access. No real provider probes were performed.

## Review checks

- The production model retains valid Claude resets with optional usage off; expired grants still disappear.
- Stable item IDs preserve independent choices; unavailable saved choices retain recognizable labels.
- Hiding Extra usage preserves reset credits, quotas, and subscription notes; it does not hide Admin API spend.
- Hiding plan metadata removes only subscription notes, preserving other quota notes.
- Shared visibility projection applies to menu, Settings preview, and Overview.
- Existing visibility tests preserve provider cache identity, background refresh revision and spend ownership.
- No fetching, credential, history, notification, CLI, or global-setting storage changes.

## Local validation

- Focused regression run: 151 tests in 25 suites passed.
- Native proof/visibility run: 22 tests in one suite passed.
- `make check`: passed; zero SwiftLint violations across 2,958 files.
- Additional production-context regression: six UsageStore tests passed.
- Initial serial full `make test`: 90 groups passed, then Italian localization rejected English fallback strings.
  The strings are now translated; 95 localization, provider-boundary and production-context tests pass.
- Final `make check`: passes with zero violations.
- Full four-worker rerun: 133 groups passed; one group failed with eight placement assertions after a retry.
  The runner stopped scheduling before the remaining 16 groups ran. No timeouts. This is not a fully green suite.
- `StatusItemControllerSplitLifecycleTests` and its placement helper are unchanged from the upstream base.
  `upstream-placement-repro.swift` embeds that exact baseline helper with only logging stubbed. Running
  `swift -swift-version 6 -default-isolation MainActor .github/pr-proof/usage-visibility/upstream-placement-repro.swift`
  prints `prepare=true, namedRemoved=true, legacyRemoved=false`, reproducing a failing baseline assertion.

## Limits

New checkbox/help strings are translated in all app locales. These translations still need linguistic review.
The revised global-setting wording is English only in this patch.
The installed development app was not replaced; unrelated CodexBar-dev changes remain intact.
The native renders validate component layout, not an end-to-end live-account session.
