// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Nice",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .executable(name: "Nice", targets: ["Nice"]),
        .library(name: "NiceTypes", targets: ["NiceTypes"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.13.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-auth", from: "2.0.2"),
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.3"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.4")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "Nice",
            dependencies: [
                "CryptoSwift",
                "NiceTypes",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdAuth", package: "hummingbird-auth"),
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            resources: [
                .copy("Resources/secrets.json")
            ]
        ),
        .target(name: "NiceTypes"),
        .testTarget(name: "NiceTests", dependencies: [
            "Nice"
        ])
    ],
)
