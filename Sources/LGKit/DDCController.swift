import Dispatch
import Foundation

public protocol I2CTransport: AnyObject {
    func write(dataAddress: UInt32, bytes: [UInt8]) -> Bool
    func read(dataAddress: UInt32, count: Int) -> [UInt8]?
}

public enum DDCError: Error, Equatable {
    case noReply(code: UInt8)
    case writeFailed(code: UInt8)
}

/// DDC/CI conversation with one monitor. Timings are the ones verified on the LG.
public final class DDCController: @unchecked Sendable {
    private static let replyWait: useconds_t = 50_000
    private static let setWait: useconds_t = 20_000
    private static let commandGap: UInt64 = 50_000   // µs between commands
    private static let attempts = 3

    private let transport: I2CTransport
    private let sleep: (useconds_t) -> Void
    private let lock = NSLock()
    private var lastFinished: DispatchTime?
    private var rawReply: [UInt8]?

    public init(transport: I2CTransport, sleep: @escaping (useconds_t) -> Void = { usleep($0) }) {
        self.transport = transport
        self.sleep = sleep
    }

    /// The bytes of the last get reply that parsed, for `lgctl read --raw` diagnostics.
    public var lastRawReply: [UInt8]? {
        lock.lock(); defer { lock.unlock() }
        return rawReply
    }

    public func read(_ code: UInt8) throws -> VCPReading {
        lock.lock(); defer { lock.unlock() }
        waitForGap()
        defer { lastFinished = .now() }
        for attempt in 0..<Self.attempts {
            if attempt > 0 { sleep(Self.replyWait) }
            _ = transport.write(dataAddress: DDCPacket.dataAddress, bytes: DDCPacket.getRequest(code))
            sleep(Self.replyWait)
            if let reply = transport.read(dataAddress: DDCPacket.dataAddress, count: 11),
               let reading = DDCPacket.parseGetReply(reply, code: code) {
                rawReply = reply
                return reading
            }
        }
        throw DDCError.noReply(code: code)
    }

    public func write(_ code: UInt8, value: UInt16) throws {
        lock.lock(); defer { lock.unlock() }
        waitForGap()
        defer { lastFinished = .now() }
        let packet = DDCPacket.setRequest(code, value: value)
        // The LG can drop a lone set, so send it twice and only fail if neither went out.
        let first = transport.write(dataAddress: DDCPacket.dataAddress, bytes: packet)
        sleep(Self.setWait)
        let second = transport.write(dataAddress: DDCPacket.dataAddress, bytes: packet)
        sleep(Self.setWait)
        if !first && !second { throw DDCError.writeFailed(code: code) }
    }

    public func capabilities() throws -> String {
        lock.lock(); defer { lock.unlock() }
        var data: [UInt8] = []
        while data.count < 2048 {
            waitForGap()
            let offset = UInt16(data.count)
            let chunk = try capabilitiesChunk(offset: offset)
            lastFinished = .now()
            if chunk.isEmpty { break }
            data += chunk
        }
        while data.last == 0 { data.removeLast() }
        // Latin-1: every byte maps to the scalar of the same value.
        return String(String.UnicodeScalarView(data.map { Unicode.Scalar($0) }))
    }

    private func capabilitiesChunk(offset: UInt16) throws -> [UInt8] {
        for attempt in 0..<Self.attempts {
            if attempt > 0 { sleep(Self.replyWait) }
            _ = transport.write(dataAddress: DDCPacket.dataAddress, bytes: DDCPacket.capabilitiesRequest(offset: offset))
            sleep(Self.replyWait)
            if let reply = transport.read(dataAddress: DDCPacket.dataAddress, count: 38),
               let chunk = DDCPacket.parseCapabilitiesReply(reply, offset: offset) {
                return chunk
            }
        }
        throw DDCError.noReply(code: 0xF3)
    }

    /// Sleeps for whatever is left of the inter-command gap; nothing before the first command.
    private func waitForGap() {
        guard let last = lastFinished else { return }
        let elapsedMicros = (DispatchTime.now().uptimeNanoseconds - last.uptimeNanoseconds) / 1_000
        if elapsedMicros < Self.commandGap { sleep(useconds_t(Self.commandGap - elapsedMicros)) }
    }
}
