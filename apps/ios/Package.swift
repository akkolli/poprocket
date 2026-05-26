// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PopRocket",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PopRocketKit", targets: ["PopRocketKit"]),
        .library(name: "PopRocketApp", targets: ["PopRocketApp"]),
        .library(name: "PopRocketWidget", targets: ["PopRocketWidget"]),
        .library(name: "PopRocketIntents", targets: ["PopRocketIntents"]),
        .library(name: "PopRocketNotificationService", targets: ["PopRocketNotificationService"])
    ],
    targets: [
        .target(name: "PopRocketKit"),
        .target(name: "PopRocketApp", dependencies: ["PopRocketKit"]),
        .target(name: "PopRocketWidget", dependencies: ["PopRocketKit", "PopRocketIntents"]),
        .target(name: "PopRocketIntents", dependencies: ["PopRocketKit"]),
        .target(name: "PopRocketNotificationService", dependencies: ["PopRocketKit"]),
        .testTarget(name: "PopRocketKitTests", dependencies: ["PopRocketKit"])
    ]
)
