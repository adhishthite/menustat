// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MenuStat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MenuStatCore", targets: ["MenuStatCore"]),
        .executable(name: "MenuStat", targets: ["MenuStat"]),
        .executable(name: "menustat", targets: ["MenuStatCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.7.1")),
        .package(url: "https://github.com/pakLebah/ANSITerminal", exact: "0.0.3")
    ],
    targets: [
        .target(
            name: "MenuStatCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "MenuStat",
            dependencies: ["MenuStatCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .target(
            name: "MenuStatCLIKit",
            dependencies: [
                "MenuStatCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "ANSITerminal"
            ]
        ),
        .executableTarget(
            name: "MenuStatCLI",
            dependencies: ["MenuStatCLIKit"]
        ),
        .testTarget(
            name: "MenuStatTests",
            dependencies: [
                "MenuStat",
                "MenuStatCLIKit",
                "MenuStatCore"
            ]
        )
    ]
)
