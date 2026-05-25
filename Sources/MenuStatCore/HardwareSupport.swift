import Darwin

public enum HardwareSupport {
    public static let unsupportedTitle = "MenuStat requires Apple Silicon"
    public static let unsupportedMessage = """
    MenuStat reads Apple Silicon-specific CPU, GPU, memory pressure, and fan telemetry.

    This Mac does not appear to be an Apple Silicon Mac. MenuStat will now quit.
    """

    public static var isAppleSiliconMac: Bool {
        sysctlOptionalARM64Value() == 1
    }

    static func isAppleSiliconMac(optionalARM64Value value: Int32?) -> Bool {
        value == 1
    }

    private static func sysctlOptionalARM64Value() -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        guard result == 0 else { return nil }
        return value
    }
}
