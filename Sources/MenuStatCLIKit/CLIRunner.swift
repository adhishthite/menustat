import ANSITerminal
import Darwin
import Foundation
import MenuStatCore

final class CLIRunner {
    private let sampler: SystemSampler
    private let output: (String) -> Void

    init(sampler: SystemSampler = SystemSampler(), output: @escaping (String) -> Void = { print($0) }) {
        self.sampler = sampler
        self.output = output
    }

    func runDashboard(interval: Double) throws {
        try requireSupportedHardware()

        guard isTerminal(STDOUT_FILENO) else {
            output(CLIRenderer.plainSnapshot(snapshot: sample(instant: false)))
            return
        }

        installInterruptHandler()
        cursorOff()
        defer {
            cursorOn()
            setDefault(color: true, style: true)
        }

        while true {
            let snapshot = sample(instant: false)
            clearScreen()
            output(CLIRenderer.dashboard(snapshot: snapshot, interval: interval, width: terminalWidth()))

            let end = Date().addingTimeInterval(interval)
            while Date() < end {
                if keyPressed(), readChar().lowercased() == "q" {
                    return
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    func runSnapshot(json: Bool, instant: Bool) throws {
        try requireSupportedHardware()
        let snapshot = sample(instant: instant)
        try output(json ? CLIJSON.snapshot(snapshot) : CLIRenderer.plainSnapshot(snapshot: snapshot))
    }

    func runTop(sort: TopSort, limit: Int, json: Bool) throws {
        try requireSupportedHardware()
        let snapshot = sample(instant: false)
        try output(json ? CLIJSON.top(snapshot, sort: sort, limit: limit) : CLIRenderer.top(snapshot: snapshot, sort: sort, limit: limit))
    }

    func runFans(json: Bool) throws {
        try requireSupportedHardware()
        let snapshot = sample(instant: true)
        try output(json ? CLIJSON.fans(snapshot.fans) : CLIRenderer.fans(snapshot: snapshot))
    }

    private func sample(instant: Bool) -> SystemSnapshot {
        guard !instant else {
            return sampler.sample(includeAppUsage: true)
        }

        _ = sampler.sample(includeAppUsage: false)
        sampler.refreshProcessUsageBaseline()
        Thread.sleep(forTimeInterval: 0.25)
        return sampler.sample(includeAppUsage: true)
    }

    private func requireSupportedHardware() throws {
        guard HardwareSupport.isAppleSiliconMac else {
            throw CLIError.unsupportedHardware
        }
    }

    private func isTerminal(_ fileDescriptor: Int32) -> Bool {
        isatty(fileDescriptor) == 1
    }

    private func terminalWidth() -> Int {
        var size = winsize()
        let result = ioctl(STDOUT_FILENO, TIOCGWINSZ, &size)
        guard result == 0, size.ws_col > 0 else { return 88 }
        return Int(size.ws_col)
    }
}

private func installInterruptHandler() {
    signal(SIGINT) { _ in
        cursorOn()
        setDefault(color: true, style: true)
        exit(130)
    }
}

enum CLIError: Error, CustomStringConvertible {
    case unsupportedHardware

    var description: String {
        switch self {
        case .unsupportedHardware:
            HardwareSupport.unsupportedMessage
        }
    }
}
