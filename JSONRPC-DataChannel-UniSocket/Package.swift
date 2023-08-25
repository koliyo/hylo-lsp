// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JSONRPC-DataChannel-UniSocket",
    platforms: [
      .macOS(.v13)
    ],

    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "JSONRPC-DataChannel-UniSocket",
            targets: ["JSONRPC-DataChannel-UniSocket"]),
    ],

    dependencies: [
      .package(path: "../swift-unisocket"),
      .package(url: "https://github.com/ChimeHQ/JSONRPC", from: "0.8.0"),
    ],

    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "JSONRPC-DataChannel-UniSocket",
            dependencies: [
              "JSONRPC",
              .product(name: "UniSocket", package: "swift-unisocket"),
            ]),
        .testTarget(
            name: "JSONRPC-DataChannel-UniSocketTests",
            dependencies: ["JSONRPC-DataChannel-UniSocket"]),
    ]
)
