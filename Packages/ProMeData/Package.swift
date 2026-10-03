// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProMeData",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ProMeData", targets: ["ProMeData"])
    ],
    dependencies: [
        .package(path: "../ProMeDomain")
    ],
    targets: [
        .target(
            name: "ProMeData",
            dependencies: ["ProMeDomain"],
            resources: [
                .process("Model")
            ]
        )
    ]
)
