/// Decides when a monitor refresh runs.
///
/// A refresh takes seconds when the LG doesn't answer, so overlapping requests must not queue up
/// timeouts. Dropping them outright is wrong too: a request that arrives mid-refresh (a hot-plug,
/// a wake, an input switch) may see a state the running refresh already missed. So every request
/// made while one runs collapses into a single rerun once it finishes.
public struct RefreshCoalescer: Sendable {
    public private(set) var isRunning = false
    private var pending = false

    public init() {}

    /// Returns true when the caller should start a refresh now.
    public mutating func request() -> Bool {
        guard !isRunning else {
            pending = true
            return false
        }
        isRunning = true
        return true
    }

    /// Call when a refresh has applied. Returns true when the caller should run it again.
    public mutating func finished() -> Bool {
        isRunning = false
        defer { pending = false }
        return pending
    }
}
