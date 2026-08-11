import Foundation

/// Minimal lock-guarded box for values shared across concurrency domains,
/// used by the SwiftData migration stages instead of `nonisolated(unsafe)`
/// statics.
final class LockIsolated<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
