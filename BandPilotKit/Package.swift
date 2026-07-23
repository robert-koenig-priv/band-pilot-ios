// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BandPilotKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BandPilotKit", targets: ["BandPilotKit"]),
    ],
    targets: [
        .target(
            name: "BandPilotKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BandPilotKitTests",
            dependencies: ["BandPilotKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
