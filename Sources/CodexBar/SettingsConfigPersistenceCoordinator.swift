import CodexBarCore
import Foundation

/// Reloads invalidate every older snapshot. Only the final publication and reload read share
/// this lock; staging and fsync never hold it or need the main actor.
final class SettingsConfigPersistenceCoordinator: @unchecked Sendable {
    struct WritePermit: Sendable {
        fileprivate let coordinator: SettingsConfigPersistenceCoordinator
        fileprivate let generation: UInt64

        func beginPublication() -> Bool {
            self.coordinator.lock.lock()
            guard self.generation == self.coordinator.generation else {
                self.coordinator.lock.unlock()
                return false
            }
            return true
        }

        func endPublication() {
            self.coordinator.lock.unlock()
        }
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0

    func makeWritePermit() -> WritePermit {
        self.lock.withLock { WritePermit(coordinator: self, generation: self.generation) }
    }

    func load(_ store: CodexBarConfigStore) throws -> CodexBarConfig? {
        try self.lock.withLock {
            self.generation &+= 1
            return try store.load()
        }
    }
}
