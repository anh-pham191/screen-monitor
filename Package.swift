// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LGControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LGKit"),
        .executableTarget(name: "lgctl", dependencies: ["LGKit"]),
        .executableTarget(name: "LGControl", dependencies: ["LGKit"]),
        .testTarget(name: "LGKitTests", dependencies: ["LGKit"]),
    ],
    swiftLanguageModes: [.v5]
)
