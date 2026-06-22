// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlashFlow",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FlashFlow", targets: ["FlashFlow"]),
        .executable(name: "FlashFlowBridge", targets: ["FlashFlowBridge"])
    ],
    targets: [
        .executableTarget(
            name: "FlashFlow",
            path: "Sources/FlashFlow"
        ),
        .executableTarget(
            name: "FlashFlowBridge",
            path: "Sources/FlashFlowBridge"
        )
    ],
    swiftLanguageVersions: [.v5]
)
