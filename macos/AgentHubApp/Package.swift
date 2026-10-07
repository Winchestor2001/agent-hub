// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentHubApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentHubApp", targets: ["AgentHubApp"])
    ],
    targets: [
        .executableTarget(name: "AgentHubApp")
    ]
)
