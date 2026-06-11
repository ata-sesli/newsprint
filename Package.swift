// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "newsprint",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "newsprint", targets: ["newsprint"]),
        .library(name: "newsprintCore", targets: ["newsprintCore"])
    ],
    targets: [
        .target(
            name: "newsprintCore"
        ),
        .executableTarget(
            name: "newsprint",
            dependencies: ["newsprintCore"]
        ),
        .testTarget(
            name: "newsprintTests",
            dependencies: ["newsprintCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
