// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeoGlossaCore",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "NeoGlossaCore", targets: ["NeoGlossaCore"])
    ],
    targets: [
        .target(name: "NeoGlossaCore"),
        .testTarget(name: "NeoGlossaCoreTests", dependencies: ["NeoGlossaCore"]),
    ]
)
