// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ResolutionLab",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "ResolutionCore", targets: ["ResolutionCore"])],
    targets: [
        .target(name: "ResolutionCore"),
        .testTarget(
            name: "ResolutionCoreTests",
            dependencies: ["ResolutionCore"],
            resources: [.process("Fixtures")]
        )
    ]
)
