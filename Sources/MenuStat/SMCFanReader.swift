import Foundation
import IOKit

final class SMCFanReader {
    private let services = ["AppleSMCKeysEndpoint", "AppleSMC"]
    private var cachedConnection: (service: String, connection: io_connect_t)?
    private var cachedUnavailableSnapshot: FanSnapshot?

    deinit {
        closeCachedConnection()
    }

    func readFans() -> FanSnapshot {
        #if !arch(arm64)
        return .unavailable("MenuStat fan checks are Apple Silicon only.")
        #else
        if let cachedUnavailableSnapshot {
            return cachedUnavailableSnapshot
        }

        if let cachedConnection {
            switch readFans(service: cachedConnection.service, connection: cachedConnection.connection) {
            case let .available(snapshot):
                return snapshot
            case let .unavailable(snapshot, _):
                closeCachedConnection()
                return snapshot
            case .failed:
                closeCachedConnection()
            }
        }

        var lastMessage = "Could not query Apple Silicon fan sensors."
        var shouldCacheUnavailable = false
        var unavailableSnapshot: FanSnapshot?
        for service in services {
            let connectionResult = openConnection(service: service)
            guard let connection = connectionResult.connection else {
                if let message = connectionResult.message {
                    lastMessage = message
                    shouldCacheUnavailable = shouldCacheUnavailable || connectionResult.cacheUnavailable
                }
                continue
            }

            switch readFans(service: service, connection: connection) {
            case let .available(snapshot):
                cachedConnection = (service: service, connection: connection)
                return snapshot
            case let .unavailable(snapshot, cache):
                IOServiceClose(connection)
                lastMessage = snapshot.message ?? lastMessage
                if cache {
                    unavailableSnapshot = snapshot
                }
            case let .failed(message):
                IOServiceClose(connection)
                lastMessage = message
            }
        }

        if let unavailableSnapshot {
            cachedUnavailableSnapshot = unavailableSnapshot
            return unavailableSnapshot
        }

        let snapshot = FanSnapshot.unavailable(
            lastMessage,
            source: services.joined(separator: " / "),
            attemptedKeys: ["FNum", "F0Ac", "F1Ac", "F2Ac", "F3Ac"]
        )
        if shouldCacheUnavailable {
            cachedUnavailableSnapshot = snapshot
        }
        return snapshot
        #endif
    }

    private func openConnection(service: String) -> FanConnectionOpenResult {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching(service)
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return FanConnectionOpenResult(message: "Could not query \(service).", cacheUnavailable: false)
        }
        defer { IOObjectRelease(iterator) }

        let device = IOIteratorNext(iterator)
        guard device != 0 else {
            return FanConnectionOpenResult(message: "\(service) is not exposed on this Mac.", cacheUnavailable: true)
        }
        defer { IOObjectRelease(device) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(device, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            return FanConnectionOpenResult(message: "\(service) refused SMC user-client access.", cacheUnavailable: true)
        }
        return FanConnectionOpenResult(connection: connection)
    }

    private func closeCachedConnection() {
        guard let cachedConnection else { return }
        IOServiceClose(cachedConnection.connection)
        self.cachedConnection = nil
    }

    private func readFans(service: String, connection: io_connect_t) -> FanReadResult {
        guard let detectedCountValue = readUnsignedInteger(key: "FNum", connection: connection) else {
            return .failed("\(service) opened, but FNum could not be read.")
        }

        let detectedCount = Int(detectedCountValue)
        let probeCount = max(detectedCount, 4)
        let attemptedKeys = (0..<probeCount).flatMap { index in
            ["F\(index)Ac", "F\(index)Mn", "F\(index)Mx"]
        }

        var speeds: [Int] = []
        var minSpeeds: [Int] = []
        var maxSpeeds: [Int] = []
        for index in 0..<probeCount {
            guard let rpm = readFanRPM(key: "F\(index)Ac", connection: connection), rpm >= 0 else { continue }
            speeds.append(Int(rpm.rounded()))
            minSpeeds.append(Int((readFanRPM(key: "F\(index)Mn", connection: connection) ?? 0).rounded()))
            maxSpeeds.append(Int((readFanRPM(key: "F\(index)Mx", connection: connection) ?? 0).rounded()))
        }

        if !speeds.isEmpty {
            return .available(
                FanSnapshot(
                    speeds: speeds,
                    minSpeeds: minSpeeds,
                    maxSpeeds: maxSpeeds,
                    message: nil,
                    source: service,
                    attemptedKeys: attemptedKeys
                )
            )
        }

        let message = detectedCount == 0
            ? "\(service) opened, but FNum did not report fans."
            : "\(service) reported \(detectedCount) fan(s), but RPM keys were empty."
        return .unavailable(
            .unavailable(message, source: service, attemptedKeys: attemptedKeys),
            cache: true
        )
    }

    private func readUnsignedInteger(key: String, connection: io_connect_t) -> UInt32? {
        guard let data = readKey(key, connection: connection), !data.bytes.isEmpty else { return nil }
        return data.bytes.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
    }

    private func readFanRPM(key: String, connection: io_connect_t) -> Double? {
        guard let data = readKey(key, connection: connection) else { return nil }
        if data.size == 4, data.bytes.count >= 4 {
            return Double(data.bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        }
        guard data.bytes.count >= 2 else { return nil }
        let raw = UInt16(data.bytes[0]) << 8 | UInt16(data.bytes[1])
        return Double(raw) / 4.0
    }

    private func readKey(_ key: String, connection: io_connect_t) -> (bytes: [UInt8], size: UInt32)? {
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        input.key = key.smcKey
        input.data8 = SMCCommand.readKeyInfo.rawValue

        guard callSMC(connection: connection, input: &input, output: &output) == KERN_SUCCESS else {
            return nil
        }

        let dataSize = output.keyInfo.dataSize
        input.keyInfo = output.keyInfo
        input.keyInfo.dataSize = dataSize
        input.data8 = SMCCommand.readBytes.rawValue

        guard callSMC(connection: connection, input: &input, output: &output) == KERN_SUCCESS else {
            return nil
        }

        return (Array(output.dataBytes.prefix(Int(dataSize))), dataSize)
    }

    private func callSMC(connection: io_connect_t, input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        return withUnsafeMutablePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inputPointer,
                    inputSize,
                    outputPointer,
                    &outputSize
                )
            }
        }
    }
}

private enum FanReadResult {
    case available(FanSnapshot)
    case unavailable(FanSnapshot, cache: Bool)
    case failed(String)
}

private struct FanConnectionOpenResult {
    let connection: io_connect_t?
    let message: String?
    let cacheUnavailable: Bool

    init(connection: io_connect_t) {
        self.connection = connection
        message = nil
        cacheUnavailable = false
    }

    init(message: String, cacheUnavailable: Bool) {
        connection = nil
        self.message = message
        self.cacheUnavailable = cacheUnavailable
    }
}

private enum SMCCommand: UInt8 {
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes = (
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
    )
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private extension String {
    var smcKey: UInt32 {
        utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
    }
}

private extension SMCParamStruct {
    var dataBytes: [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0) }
    }
}
