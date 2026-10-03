// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProMeDomain",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ProMeDomain", targets: ["ProMeDomain"])
    ],
    targets: [
        .target(name: "ProMeDomain")
    ]
)
