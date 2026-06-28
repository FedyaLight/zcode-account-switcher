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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
    ],
    targets: [
        .target(
            name: "ZCodeAccountSwitcherCore",
            path: "Sources/ZCodeAccountSwitcherCore"
        ),
        .executableTarget(
            name: "ZCodeAccountSwitcher",
            dependencies: [
                "ZCodeAccountSwitcherCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/ZCodeAccountSwitcher"
        ),
        .testTarget(
            name: "ZCodeAccountSwitcherCoreTests",
            dependencies: ["ZCodeAccountSwitcherCore"],
            path: "Tests/ZCodeAccountSwitcherCoreTests"
        )
    ]
)
