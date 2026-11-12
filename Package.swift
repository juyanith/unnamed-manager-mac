// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "UnnamedManager",
    platforms: [.macOS(.v27)],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "UnnamedManagerKit"),
        .executableTarget(
            name: "UnnamedManager",
            dependencies: ["UnnamedManagerKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "UnnamedManagerKitTests", dependencies: ["UnnamedManagerKit"],
                    // Golden files the tests read by path (S-060), not resources.
                    exclude: ["Golden"]),
    ]
)
