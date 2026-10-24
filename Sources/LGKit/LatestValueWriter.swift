import Foundation

/// Rate-limits a stream of values (e.g. a slider drag) so the DDC bus is not flooded:
/// the first value goes out immediately, then only the newest one per `interval`.
public final class LatestValueWriter<Value: Sendable>: @unchecked Sendable {
    private let queue: DispatchQueue
    private let interval: TimeInterval
    private let write: (Value) -> Void
    private let lock = NSLock()
    private var coolingDown = false
    private var pending: Value?

    public init(queue: DispatchQueue, interval: TimeInterval, write: @escaping (Value) -> Void) {
        self.queue = queue
        self.interval = interval
        self.write = write
    }

    public func submit(_ value: Value) {
        lock.lock()
        if coolingDown {
            pending = value
            lock.unlock()
            return
        }
        coolingDown = true
        lock.unlock()
        send(value)
    }

    private func send(_ value: Value) {
        queue.async { [self] in
            write(value)
            queue.asyncAfter(deadline: .now() + interval) { [self] in coolDownEnded() }
        }
    }

    private func coolDownEnded() {
        lock.lock()
        guard let next = pending else {
            coolingDown = false
            lock.unlock()
            return
        }
        pending = nil
        lock.unlock()
        send(next)
    }
}
