// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "deployramp-swift",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(name: "DeployRamp", targets: ["DeployRamp"])
    ],
    targets: [
        .target(name: "DeployRamp")
    ]
)
