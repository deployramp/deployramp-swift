import Foundation

/// Manages a stable user ID for the current process.
enum UserIdProvider {
    /// A cached user ID, generated once per process lifetime.
    private static var cachedUserId: String?
    private static let lock = NSLock()

    /// Returns a stable user ID. Generated on first call, then cached.
    static func getUserId() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let existing = cachedUserId {
            return existing
        }
        let id = UUID().uuidString
        cachedUserId = id
        return id
    }

    /// Resets the cached user ID. Used internally for testing/close.
    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        cachedUserId = nil
    }
}
