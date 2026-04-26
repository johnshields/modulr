// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kurley",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Kurley", targets: ["Kurley"])
    ],
    dependencies: [
        .package(url: "https://github.com/chicio/ID3TagEditor.git", from: "4.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Kurley",
            dependencies: [
                .product(name: "ID3TagEditor", package: "ID3TagEditor")
            ],
            path: "Kurley",
            resources: [.process("Resources")]
        )
    ]
)
