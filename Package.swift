// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LLimit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LLimit", targets: ["LLimit"])
    ],
    targets: [
        .executableTarget(
            name: "LLimit",
            path: "Sources/LLimit"
        ),
        .testTarget(name: "LLimitTests", dependencies: ["LLimit"])
    ]
)
