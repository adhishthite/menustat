// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MenuStat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MenuStat", targets: ["MenuStat"])
    ],
    targets: [
        .executableTarget(
            name: "MenuStat",
            swiftSettings: [
                .unsafeFlags(["-target", "arm64-apple-macos13.0"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "MenuStatTests",
            dependencies: ["MenuStat"],
            swiftSettings: [
                .unsafeFlags(["-target", "arm64-apple-macos13.0"])
            ]
        )
    ]
)
