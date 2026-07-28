import Foundation

/// A value behind a lock.
///
/// `Synchronization.Mutex` would be the modern answer, but it requires macOS 15
/// and it is the only thing in this app that does. Trading it for a lock and a
/// box moves the floor down two whole releases, which is worth more than the
/// newer type.
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) { self.value = value }

    @discardableResult
    public func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
