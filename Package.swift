// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation


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
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    .package(url: "https://github.com/crspybits/swift-log-file.git", from: "0.1.0"),
    // .package(url: "https://github.com/vapor/console-kit.git", from: "4.7.0"),
    // .package(url: "https://github.com/ChimeHQ/LanguageServerProtocol", from: "0.10.0"),
    // .package(url: "https://github.com/ChimeHQ/LanguageClient", from: "0.6.0"),
    // .package(url: "https://github.com/ChimeHQ/ProcessEnv", from: "1.0.0"),
    // .package(url: "https://github.com/seznam/swift-unisocket", from: "0.14.0"),
    .package(path: "./LanguageServerProtocol"),
    .package(path: "./LanguageClient"),
    // .package(name: "UniSocket", path: "./swift-unisocket"),
    // .package(path: "./swift-unisocket"),
    .package(path: "./JSONRPC-DataChannel-UniSocket"),
    .package(path: "./JSONRPC-DataChannel-Actor"),
    .package(path: "./JSONRPC-DataChannel-StdioPipe"),
    .package(path: "./hylo")
  ],
  targets: [

    .target(
      name: "hylo-lsp",
      // dependencies: ["LanguageServerProtocol", "LanguageClient"],
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
        .product(name: "FileLogging", package: "swift-log-file"),
        .product(name: "LanguageServerProtocol", package: "LanguageServerProtocol"),
        .product(name: "LanguageServerProtocol-Server", package: "LanguageServerProtocol"),
        // "JSONRPC-DataChannel-UniSocket",
        // "JSONRPC-DataChannel-Actor",
        .product(name: "Hylo", package: "hylo"),
        // .product(name: "UniSocket", package: "swift-unisocket"),
        // .product(name: "ProcessEnv", package: "ProcessEnv", condition: .when(platforms: [.macOS])),
      ],
      path: "Sources/hylo-lsp"
      // exclude: ["hylo-lsp-server/main.swift"]
    ),


    .executableTarget(
      name: "hylo-lsp-server",
      // dependencies: ["LanguageServerProtocol", "LanguageClient"],
      dependencies: [
        "hylo-lsp",
        "JSONRPC-DataChannel-UniSocket",
        "JSONRPC-DataChannel-Actor",
        "JSONRPC-DataChannel-StdioPipe",
        // .product(name: "ProcessEnv", package: "ProcessEnv", condition: .when(platforms: [.macOS])),
      ],
      // dependencies: ["LanguageServerProtocol", "UniSocket"],
      path: "Sources/hylo-lsp-server"
    ),

    .executableTarget(
      name: "hylo-lsp-client",
      // dependencies: ["LanguageServerProtocol", "LanguageClient"],
      dependencies: [
        // .product(name: "ConsoleKit", package: "console-kit"),
        "hylo-lsp",
        "LanguageClient",
        "JSONRPC-DataChannel-UniSocket",
        "JSONRPC-DataChannel-Actor",
        "JSONRPC-DataChannel-StdioPipe",
      ],
      // dependencies: ["LanguageServerProtocol", "UniSocket"],
      path: "Sources/hylo-lsp-client"
    ),


    // .executableTarget(
    //   name: "hylo-lsp-client",
    //   // dependencies: ["LanguageServerProtocol", "LanguageClient"],
    //   dependencies: [
    //     "LanguageServerProtocol",
    //     // "UniSocket",
    //     .product(name: "UniSocket", package: "swift-unisocket"),
    //     .product(name: "ProcessEnv", package: "ProcessEnv", condition: .when(platforms: [.macOS])),
    //   ],
    //   // dependencies: ["LanguageServerProtocol", "UniSocket"],
    //   path: "Client"
    // ),

    // .target(
    //   name: "hylo-lsp"),
    .testTarget(
      name: "hylo-lspTests",
      dependencies: ["hylo-lsp-server"]),
  ]
)
