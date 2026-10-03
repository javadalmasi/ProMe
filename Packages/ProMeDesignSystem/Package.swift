// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProMeDesignSystem",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "ProMeDesignSystem", targets: ["ProMeDesignSystem"])
    ],
    dependencies: [
        .package(path: "../ProMeDomain")
    ],
    targets: [
        .target(
            name: "ProMeDesignSystem",
            dependencies: ["ProMeDomain"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
