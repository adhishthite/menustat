import ArgumentParser
import Foundation

public struct MenuStatCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "menustat",
        abstract: "Observe Apple Silicon CPU, memory, GPU, pressure, fans, and top app usage.",
        subcommands: [
            Dashboard.self,
            Snapshot.self,
            Top.self,
            Fans.self
        ],
        defaultSubcommand: Dashboard.self
    )

    public init() {}
}

struct Dashboard: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dashboard",
        abstract: "Show a live terminal dashboard."
    )

    @Option(help: "Refresh interval in seconds.") var interval: Double = 2

    func validate() throws {
        guard interval > 0 else {
            throw ValidationError("--interval must be greater than 0.")
        }
    }

    func run() throws {
        try CLIRunner().runDashboard(interval: interval)
    }
}

struct Snapshot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Print one system snapshot."
    )

    @Flag(help: "Print machine-readable JSON.") var json = false

    @Flag(help: "Skip warm-up sampling.") var instant = false

    func run() throws {
        try CLIRunner().runSnapshot(json: json, instant: instant)
    }
}

struct Top: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "top",
        abstract: "Print top app usage."
    )

    @Option(help: "Sort by cpu, memory, or heat.") var by: TopSort = .cpu

    @Option(help: "Maximum number of apps to print.") var limit = 10

    @Flag(help: "Print machine-readable JSON.") var json = false

    func validate() throws {
        guard (1...30).contains(limit) else {
            throw ValidationError("--limit must be between 1 and 30.")
        }
    }

    func run() throws {
        try CLIRunner().runTop(sort: by, limit: limit, json: json)
    }
}

struct Fans: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fans",
        abstract: "Print fan RPM and range information."
    )

    @Flag(help: "Print machine-readable JSON.") var json = false

    func run() throws {
        try CLIRunner().runFans(json: json)
    }
}
