# Interactive visibility and upgrade proof for PR #4484

Feature source: `11492b990ce69c36272c8c50a1e52d128dd422c6`.

These artifacts live on a separate fork-only proof branch. They are not part of the upstream feature branch,
its diff, or its commit ancestry. All provider input is synthetic; no account identity, endpoint, credential,
browser-cookie import, or live provider request was used. Screenshots are unedited native app-window captures.

## What was exercised

A freshly built Debug `CodexBar` executable ran through `CodexBarEntryPoint` with a local, opt-in proof hook.
The hook injects synthetic snapshots and an old-format on-disk configuration, then hosts the production
`ProvidersPane`, `UsageMenuCardView`, and `OverviewMenuCardRowView`. The actual provider checkboxes write through
`SettingsStore`; the cards read through `UsageStore.menuCardModel`. Model fields are not manually removed to
simulate visibility. The small top-level global toggle binds the production global setting directly.

The application really quits and starts as a new process against the same configuration and defaults files.
The before/after receipts have different PIDs and identical visibility selections and model output.

This is an instrumented built-app proof with a contained synthetic startup delegate. It does not exercise
normal live-provider startup, the OS status-menu open/close lifecycle, or a signed release installation.
The production settings, shared card builders, Overview views, and config persistence are exercised.
Instrumentation and proof files are absent from the upstream source and commits.

`UsageVisibilityProofApp.swift`, `ProofDefaults.swift`, and `entrypoint.patch` document the local hook.
`build.json` pins the source commit and binary hash. The build command was `swift build --product CodexBar`.
The fixture process was launched with `SWIFT_TESTING=1`, `CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1`,
`CODEXBAR_TEST_CODEX_FILE_ISOLATION=1`, and `CODEXBAR_TEST_SESSION_FILE_ISOLATION=1`.
Only this proof app opts into Aqua appearance for readable screenshots; system appearance was not changed.

## Native UI transitions

| Capture | Action and observed result |
| --- | --- |
| `light-01-upgrade-preserved` | Old global setting off and old Weekly selection hidden: migration keeps reset credits unchecked; plan date remains visible. |
| `light-02-reset-enabled` | Click the real Limit Reset Credits checkbox: resets appear in Settings preview, provider card and Overview with the global switch still off. |
| `light-03-plan-hidden` | Uncheck Plan renewal / expiry: its row disappears while resets remain visible. |
| `light-04-global-on` | Enable the global optional setting: Extra usage appears; independent plan/reset choices remain unchanged. |
| `light-05-extra-hidden-before-restart` | Uncheck Extra usage: it disappears while resets remain visible. |
| `light-06-after-restart` | Quit and restart: global on, Weekly off, plan date off, Extra usage off, reset credits on all persist. |
| `light-07-independent-after-restart` | Turn global off and re-enable plan date: plan/reset choices still work independently. |
| `light-08-codex-plan-visible` | Switch to Codex: its plan date is visible in detailed cards and absent in Compact Overview. |
| `light-09-codex-plan-hidden` | Uncheck Codex plan date: detailed cards also omit it. Claude's choices are retained. |
| `light-10-reset-hidden` | Uncheck Claude reset credits: they disappear without hiding the plan date. |
| `light-11-final` | Re-enable Claude reset credits with global off: resets and renewal show, Extra usage and the old hidden Weekly lane remain hidden. |

Every image has a corresponding JSON receipt. `transitions.jsonl` is recorded by the running app.
`verify-receipts.py` checks all eleven states, disk/model parity, retained old choices and real restart persistence.

## Regression and compatibility validation

- Focused final run: 130 tests in eight suites passed, including old config JSON with and without saved item IDs,
  both global preference values, repeat launch, unknown IDs, source/color/enabled field retention,
  cross-provider isolation, new and old sync payloads, fresh defaults, and cache ownership.
- The rendered Compact Overview regression test fails for both Claude and Codex with the pre-fix PR block
  from `e99e6bc21` (the unguarded plan-date placement); it passes with the compact gate restored.
  The post-restoration run passed 56 tests in three suites. This is a rendering-block reproduction,
  not a claim that upstream main has the regression.
- `make check` passed: zero SwiftLint violations in 2,958 files.
- The complete local inventory selected 1,664 selections in 150 groups. Initial execution passed 133 groups
  and stopped after one failing placement group. The remaining sixteen groups were reconstructed,
  checked against the original logged selections, and all passed. Net result: **149/150 groups passed,
  zero timeouts**. Fourteen `ProcessEnvironmentTests` known issues are intentional assertions.
- The sole failing group contains eight unchanged `StatusItemControllerSplitLifecycleTests` assertions.
  A read-only Foundation probe with no CodexBar code reads `Optional(1000)` for `Item-0` and `Item-1` from a fresh
  defaults suite: this Mac's global domain supplies those values when the suite key is absent. The test
  expects nil after removal. `placement-readonly.swift` and its output show that independent reproduction.
  No user preferences were altered to force a green run.

`validation.log` contains compact excerpts. `resume-tests.py` preserves the exact remainder-run procedure.
The upstream CI run on the new feature head remains the authoritative clean-runner check.

## Upgrade behavior proposed for maintainer approval

Existing users with a saved false global optional setting retain hidden Claude resets. A one-time,
provider-owned marker accompanies the stored selections and sync payload so enabling resets later cannot
be undone by another restart, sync, or an older payload that omits the marker. New installations retain
visible-by-default independent controls. Plan dates are not newly hidden by the global switch.

The configuration and sync additions are optional, preserve old item IDs and unknown fields, and do not
change the config or sync schema version. Maintainer approval of the independent controls remains pending.
