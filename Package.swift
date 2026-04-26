// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kurley",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Kurley", targets: ["Kurley"])
    ],
    targets: [
        .executableTarget(
            name: "Kurley",
            path: "Kurley",
            resources: [.process("Resources")]
        )
    ]
)
