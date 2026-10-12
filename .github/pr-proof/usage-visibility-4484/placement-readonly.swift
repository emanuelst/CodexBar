import Foundation

// Read only: no CodexBar code, no set/remove calls, no persistent-domain mutations.
let defaults = UserDefaults(suiteName: "ReadOnlyPlacementProbe-\(UUID().uuidString)")!
for name in ["Item-0", "Item-1"] {
    let key = "NSStatusItem Preferred Position \(name)"
    print("fresh Foundation suite \(name) = \(String(describing: defaults.object(forKey: key)))")
}
