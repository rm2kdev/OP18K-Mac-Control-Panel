// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OP1Control",
    platforms: [.macOS(.v26)],
    targets: [
        // Protocol and USB HID access, with no SwiftUI, shared by the app and the CLI.
        .target(name: "OP1Kit"),
        .executableTarget(name: "op1ctl", dependencies: ["OP1Kit"]),
        .executableTarget(
            name: "OP1Control",
            dependencies: ["OP1Kit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
