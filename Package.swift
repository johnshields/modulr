// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Modulr",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Modulr", targets: ["Modulr"])
    ],
    dependencies: [
        .package(url: "https://github.com/chicio/ID3TagEditor.git", from: "4.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Modulr",
            dependencies: [
                .product(name: "ID3TagEditor", package: "ID3TagEditor")
            ],
            path: "Modulr",
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
