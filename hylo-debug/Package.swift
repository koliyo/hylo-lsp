// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "hylo-debug",
    platforms: [
      .macOS(.v13)
    ],


    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
      .executable(name: "hylo-debug", targets: ["hylo-debug"]),
    ],
    dependencies: [
      .package(path: "../hylo"),
      .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.1.4"),
      // .package(
      // url: "https://github.com/hylo-lang/Swifty-LLVM", branch: "main"),

    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "hylo-debug",
            dependencies: [
            // .product(name: "SwiftyLLVM", package: "Swifty-LLVM"),
            .product(name: "hylo-stdlib", package: "Hylo"),
            ]
          ),

    ]
)
