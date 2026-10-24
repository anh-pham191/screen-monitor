/// A write that survives a stale controller. The cached transport goes dead after hot-plug or
/// sleep, so one failure earns a single retry on a freshly discovered controller, never more:
/// each attempt costs two sets plus their waits, and the caller is waiting to hear the result.
public enum ReconnectingWrite {
    public struct Outcome<Controller> {
        /// The controller to keep using: the rediscovered one if a retry happened, else `current`.
        public let controller: Controller?
        public let succeeded: Bool
    }

    public static func run<Controller>(current: Controller?,
                                       rediscover: () -> Controller?,
                                       write: (Controller) throws -> Void) -> Outcome<Controller> {
        if let current, (try? write(current)) != nil {
            return Outcome(controller: current, succeeded: true)
        }
        guard let fresh = rediscover() else { return Outcome(controller: nil, succeeded: false) }
        let succeeded = (try? write(fresh)) != nil
        return Outcome(controller: fresh, succeeded: succeeded)
    }
}
