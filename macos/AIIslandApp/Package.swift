// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AIIslandApp",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AIIslandApp", targets: ["AIIslandApp"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "ClaudeSessions", dependencies: ["CSQLite"]),
        .executableTarget(
            name: "AIIslandApp",
            dependencies: ["ClaudeSessions"],
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "ClaudeSessionsTests", dependencies: ["ClaudeSessions"])
    ]
)
