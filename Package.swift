// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let commonCompileSettings: [SwiftSetting] = [
	// .unsafeFlags(["-warnings-as-errors"])
	// .enableExperimentalFeature("StrictConcurrency")
	// .unsafeFlags(["-strict-concurrency=complete", "-warn-concurrency"])
]

let toolCompileSettings = commonCompileSettings + [
  .unsafeFlags(["-parse-as-library"],
    .when(platforms: [ .windows ]
  ))
]

let package = Package(
  name: "hylo-lsp",

  platforms: [
    // .macOS(.v10_15)
    .macOS(.v13)
  ],

  products: [
    .library(name: "hylo-lsp", targets: ["hylo-lsp"]),
    .executable(name: "hylo-lsp-server", targets: ["hylo-lsp-server"]),
    .executable(name: "hylo-lsp-client", targets: ["hylo-lsp-client"]),
  ],
  dependencies: [
    .package(url: "https://github.com/groue/Semaphore", from: "0.0.8"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.1.4"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    // .package(url: "https://github.com/crspybits/swift-log-file.git", from: "0.1.0"),
    .package(url: "https://github.com/sushichop/Puppy.git", from: "0.7.0"),
    // .package(url: "https://github.com/vapor/console-kit.git", from: "4.7.0"),
    .package(url: "https://github.com/koliyo/LanguageServer", branch: "main"),
    .package(url: "https://github.com/ChimeHQ/LanguageClient", from: "0.8.0"),
    .package(url: "https://github.com/nneuberger1/swift-log-console-colors.git", from: "1.0.3"),
    .package(url: "https://github.com/ChimeHQ/JSONRPC", from: "0.9.0"),
    // .package(url: "https://github.com/ChimeHQ/ProcessEnv", from: "1.0.0"),
    // .package(url: "https://github.com/seznam/swift-unisocket", from: "0.14.0"),
    // .package(path: "./LanguageServerProtocol"),
    // .package(path: "../misc/LanguageServer"),
    // .package(name: "UniSocket", path: "./swift-unisocket"),
    // .package(path: "./swift-unisocket"),
    .package(path: "./JSONRPC-DataChannel-UniSocket"),
    // .package(path: "./JSONRPC-DataChannel-Actor"),
    // .package(path: "./JSONRPC-DataChannel-StdioPipe"),
    .package(path: "./hylo")
  ],
  targets: [

    .target(
      name: "hylo-lsp",
      dependencies: [
        "Semaphore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "SwiftLogConsoleColors", package: "swift-log-console-colors"),
        // .product(name: "FileLogging", package: "swift-log-file"),
        "Puppy",
        "LanguageServer",
        // "JSONRPC-DataChannel-UniSocket",
        // "JSONRPC-DataChannel-Actor",
        .product(name: "hylo-stdlib", package: "hylo"),
        // .product(name: "UniSocket", package: "swift-unisocket"),
        // .product(name: "ProcessEnv", package: "ProcessEnv", condition: .when(platforms: [.macOS])),
      ],
      path: "Sources/hylo-lsp",
      swiftSettings: commonCompileSettings
    ),

    .executableTarget(
      name: "hylo-lsp-server",
      dependencies: [
        "hylo-lsp",
        .product(
          name: "JSONRPC-DataChannel-UniSocket",
          package: "JSONRPC-DataChannel-UniSocket",
          condition: .when(platforms: [
            .linux,
            .macOS,
            // .windows,
          ])
        ),

        // "JSONRPC-DataChannel-UniSocket",
        // "JSONRPC-DataChannel-Actor",
        // "JSONRPC-DataChannel-StdioPipe",
        // .product(name: "ProcessEnv", package: "ProcessEnv", condition: .when(platforms: [.macOS])),
      ],
      path: "Sources/hylo-lsp-server",
      swiftSettings: toolCompileSettings
    ),

    .executableTarget(
      name: "hylo-lsp-client",
      dependencies: [
        // .product(name: "ConsoleKit", package: "console-kit"),
        "hylo-lsp",
        "LanguageClient",
        .product(
          name: "JSONRPC-DataChannel-UniSocket",
          package: "JSONRPC-DataChannel-UniSocket",
          condition: .when(platforms: [
            .linux,
            .macOS,
            // .windows,
          ])
        ),

        // "JSONRPC-DataChannel-UniSocket",
        // "JSONRPC-DataChannel-Actor",
        // "JSONRPC-DataChannel-StdioPipe",
      ],
      // dependencies: ["LanguageServerProtocol", "UniSocket"],
      path: "Sources/hylo-lsp-client",
      swiftSettings: toolCompileSettings
    ),

    .testTarget(
      name: "hylo-lspTests",
      dependencies: ["hylo-lsp-server"]),
  ]
)
