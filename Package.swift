// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ZCodeAccountSwitcherMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ZCodeAccountSwitcher", targets: ["ZCodeAccountSwitcher"])
    ],
    targets: [
        .target(
            name: "ZCodeAccountSwitcherCore",
            path: "Sources/ZCodeAccountSwitcherCore"
        ),
        .executableTarget(
            name: "ZCodeAccountSwitcher",
            dependencies: ["ZCodeAccountSwitcherCore"],
            path: "Sources/ZCodeAccountSwitcher"
        ),
        .testTarget(
            name: "ZCodeAccountSwitcherCoreTests",
            dependencies: ["ZCodeAccountSwitcherCore"],
            path: "Tests/ZCodeAccountSwitcherCoreTests"
        )
    ]
)
