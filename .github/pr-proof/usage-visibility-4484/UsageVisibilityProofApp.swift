#if DEBUG
import AppKit
import CodexBarCore
import Foundation
import Observation
import SwiftUI

// Local evidence instrumentation only: synthetic input, production views, bindings and config persistence.
@MainActor
enum UsageVisibilityProofApp {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--usage-visibility-proof") else { return false }
        precondition(SettingsStore.isRunningTests && TestProcessSafety.isRunning)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = Delegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        return true
    }

    private final class Delegate: NSObject, NSApplicationDelegate {
        var window: NSWindow?
        var timer: Timer?
        var state: ProofState?
        func applicationDidFinishLaunching(_ notification: Notification) {
            do {
                let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VISIBILITY_PROOF_ROOT"]!)
                let state = try ProofState(root: root)
                self.state = state
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1170, height: 850),
                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                self.window = window
                window.title = "CodexBar — interactive visibility proof (synthetic accounts)"
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: ProofView(state: state)
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .environment(\.colorScheme, .light))
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                    MainActor.assumeIsolated { state.record() }
                }
                state.record()
            } catch { preconditionFailure("Proof initialization failed: \(error)") }
        }
        func applicationWillTerminate(_ notification: Notification) {
            self.timer?.invalidate()
            self.state?.record()
            self.state?.settings.configFileWatcher?.stop()
            self.state?.store.stopSharedSpendDashboardPublication()
        }
    }
}

@MainActor
@Observable
private final class ProofState {
    let root: URL
    let configStore: CodexBarConfigStore
    let settings: SettingsStore
    let store: UsageStore
    var selected: UsageProvider = .claude
    private var lastRecord: Data?
    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.configStore = CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json"))
        if try self.configStore.load() == nil {
            // Old-format config: existing hidden weekly lane, no new visibility IDs.
            try Data(#"{"version":1,"providers":[{"id":"claude","enabled":true,"source":"web","hiddenUsageItemIDs":["metric:secondary"]},{"id":"codex","enabled":true,"source":"cli"}]}"#.utf8)
                .write(to: self.configStore.fileURL)
        }
        KeychainAccessGate.isDisabled = true
        let defaults = ProofDefaults(fileURL: root.appendingPathComponent("defaults.json"))
        let settings = SettingsStore(userDefaults: defaults, configStore: self.configStore,
            tokenAccountStore: FileTokenAccountStore(fileURL: root.appendingPathComponent("accounts.json")),
            keychainAccessPolicy: .init(setDisabled: { _ in }, isExplicitlyDisabled: { true }),
            performInitialProviderDetection: false)
        self.settings = settings
        settings.statusChecksEnabled = false
        settings.openAIWebAccessEnabled = false
        settings.costUsageEnabled = false
        settings.refreshFrequency = .manual
        settings.hidePersonalInfo = true
        settings.launchAtLogin = false
        let environment = ["HOME": root.path, "CODEX_HOME": root.appendingPathComponent("codex-home").path,
            "XDG_CONFIG_HOME": root.appendingPathComponent("xdg-config").path]
        settings._test_managedCodexAccountStoreURL = root.appendingPathComponent("managed-accounts.json")
        settings._test_codexReconciliationEnvironment = environment
        let store = UsageStore(fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(homeDirectory: root.path, cacheTTL: 0),
            settings: settings, startupBehavior: .testing, environmentBase: environment)
        self.store = store
        store._test_providerRefreshOverride = { _ in preconditionFailure("Unexpected live transport") }
        store._test_widgetSnapshotSaveOverride = { _ in }
        let now = Date()
        for provider in [UsageProvider.claude, .codex] {
            store._setSnapshotForTesting(UsageSnapshot(
                primary: RateWindow(usedPercent: 25, windowMinutes: 300,
                    resetsAt: now.addingTimeInterval(3600), resetDescription: nil),
                secondary: RateWindow(usedPercent: 60, windowMinutes: 10080,
                    resetsAt: now.addingTimeInterval(172800), resetDescription: nil),
                providerCost: provider == .claude
                    ? ProviderCostSnapshot(used: 12, limit: 100, currencyCode: "USD", updatedAt: now) : nil,
                claudeResetCredits: provider == .claude
                    ? ClaudeRateLimitResetCreditsSnapshot(expirations: [now.addingTimeInterval(864000)], updatedAt: now) : nil,
                subscriptionRenewsAt: now.addingTimeInterval(2073600), updatedAt: now), provider: provider)
        }
    }
    func record() {
        let model = self.store.menuCardModel(for: self.selected)
        let preview = self.store.menuCardModel(for: self.selected, context: .settings)
        let json: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "entryPoint": "CodexBarEntryPoint / local debug fixture",
            "provider": self.selected.rawValue,
            "globalOptional": self.settings.showOptionalCreditsAndExtraUsage,
            "hiddenIDs": self.settings.hiddenUsageItemIDs(for: self.selected).map(\.rawValue).sorted(),
            "diskHiddenIDs": (try? self.configStore.load()?.providerConfig(for: self.selected.instanceID)?.hiddenUsageItemIDs) ?? [],
            "menuMetrics": model.metrics.map(\.id), "previewMetrics": preview.metrics.map(\.id),
            "menuResetsVisible": model.limitResetCredits != nil,
            "previewResetsVisible": preview.limitResetCredits != nil,
            "menuPlanDateVisible": !model.subscriptionNotes.isEmpty,
            "previewPlanDateVisible": !preview.subscriptionNotes.isEmpty,
            "menuExtraUsageVisible": model.providerCost != nil,
            "previewExtraUsageVisible": preview.providerCost != nil,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            guard data != self.lastRecord else { return }
            self.lastRecord = data
            try data.write(to: self.root.appendingPathComponent("state.json"), options: .atomic)
            let log = self.root.appendingPathComponent("transitions.jsonl")
            if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data + Data("\n".utf8))
        } catch { preconditionFailure("Proof receipt failed: \(error)") }
    }
}

@MainActor
private struct ProofView: View {
    @Bindable var state: ProofState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Provider", selection: self.$state.selected) {
                    Text("Claude").tag(UsageProvider.claude)
                    Text("Codex").tag(UsageProvider.codex)
                }.pickerStyle(.segmented).frame(width: 250)
                Toggle("Optional credits, spending & billing", isOn: Binding(
                    get: { self.state.settings.showOptionalCreditsAndExtraUsage },
                    set: { self.state.settings.showOptionalCreditsAndExtraUsage = $0 }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Quit proof") { NSApp.terminate(nil) }
            }.padding(.horizontal, 16)
            HStack(alignment: .top, spacing: 20) {
                ProvidersPane(provider: self.state.selected, settings: self.state.settings, store: self.state.store)
                    .id(self.state.selected).frame(width: 650)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Provider menu card").font(.headline)
                        UsageMenuCardView(model: self.state.store.menuCardModel(for: self.state.selected), width: 420)
                        Text("Detailed Overview").font(.headline)
                        OverviewMenuCardRowView(model: self.state.store.menuCardModel(for: self.state.selected),
                            storageText: nil, width: 420, layout: .detailed)
                        Text("Compact Overview").font(.headline)
                        OverviewMenuCardRowView(model: self.state.store.menuCardModel(for: self.state.selected),
                            storageText: nil, width: 420, layout: .compact)
                    }.padding(10)
                }.frame(width: 440)
            }
        }.padding(.vertical, 12)
    }
}
#endif
