// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IronFrontCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "FrontCore", targets: ["FrontCore"])],
    targets: [
        .target(name: "FrontCore", resources: [.process("Resources")]),
        .testTarget(name: "FrontCoreTests", dependencies: ["FrontCore"])
    ]
)
