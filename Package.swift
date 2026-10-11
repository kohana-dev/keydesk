// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Keydesk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KeydeskDesktop", targets: ["KeydeskApp"]),
        .executable(name: "keydesk", targets: ["KeydeskCLI"])
    ],
    targets: [
        .target(name: "KeydeskCore"),
        .executableTarget(name: "KeydeskApp", dependencies: ["KeydeskCore"]),
        .executableTarget(name: "KeydeskCLI", dependencies: ["KeydeskCore"]),
        .executableTarget(name: "KeydeskStorageProbe", dependencies: ["KeydeskCore"], path: "Tests/StorageProbe"),
        .testTarget(name: "KeydeskCoreTests", dependencies: ["KeydeskCore"]),
        .testTarget(name: "KeydeskAppTests", dependencies: ["KeydeskApp", "KeydeskCore"])
    ]
)
