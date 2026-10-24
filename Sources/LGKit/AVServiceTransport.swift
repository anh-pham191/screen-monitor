import Foundation
import IOKit

// Private IOAVService symbols, declared exactly as proven against the LG by the probe.
typealias IOAVService = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<IOAVService>?

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: IOAVService, _ chipAddress: UInt32, _ offset: UInt32, _ outputBuffer: UnsafeMutableRawPointer, _ outputBufferSize: UInt32) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: IOAVService, _ chipAddress: UInt32, _ dataAddress: UInt32, _ inputBuffer: UnsafeMutableRawPointer, _ inputBufferSize: UInt32) -> IOReturn

public final class AVServiceTransport: I2CTransport {
    private let service: IOAVService

    init(service: IOAVService) { self.service = service }

    public func write(dataAddress: UInt32, bytes: [UInt8]) -> Bool {
        var buffer = bytes
        return buffer.withUnsafeMutableBytes {
            IOAVServiceWriteI2C(service, DDCPacket.chipAddress, dataAddress, $0.baseAddress!, UInt32($0.count))
        } == kIOReturnSuccess
    }

    public func read(dataAddress: UInt32, count: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: count)
        let result = buffer.withUnsafeMutableBytes {
            IOAVServiceReadI2C(service, DDCPacket.chipAddress, dataAddress, $0.baseAddress!, UInt32(count))
        }
        return result == kIOReturnSuccess ? buffer : nil
    }
}

/// The first external display's AV service, or nil when no external display is attached.
public func findExternalTransport() -> I2CTransport? {
    var iterator = io_iterator_t()
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iterator) }
    while case let entry = IOIteratorNext(iterator), entry != 0 {
        defer { IOObjectRelease(entry) }
        let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        if location == "External",
           let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() {
            return AVServiceTransport(service: service)
        }
    }
    return nil
}
