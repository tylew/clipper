// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClipperKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ClipperKit", targets: ["ClipperKit"]),
        .library(name: "ClipperUI", targets: ["ClipperUI"]),
        .executable(name: "clipper-cli", targets: ["clipper-cli"]),
    ],
    targets: [
        .target(name: "ClipperKit"),
        .target(name: "ClipperUI", dependencies: ["ClipperKit"]),
        .executableTarget(name: "clipper-cli", dependencies: ["ClipperKit"]),
        .testTarget(name: "ClipperKitTests", dependencies: ["ClipperKit"]),
    ]
)
