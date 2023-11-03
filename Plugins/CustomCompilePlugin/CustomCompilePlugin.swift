import PackagePlugin

// https://www.polpiella.dev/an-early-look-at-swift-extensible-build-tools
// https://github.com/apple/swift-evolution/blob/main/proposals/0303-swiftpm-extensible-build-tools.md
// https://github.com/apple/swift-evolution/blob/main/proposals/0332-swiftpm-command-plugins.md

// @main struct CustomCompilePlugin: BuildToolPlugin {
//   func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
//     let outputPath = context.pluginWorkDirectory
//     let outputFilePath = outputPath.appending("GeneratedColors.swift")

//     return [
//       .prebuildCommand(
//         displayName: "CustomCompile",
//         // Can also be used with a binaryTarget defined as follows
//         // try context.tool(named:"swiftgen").path
//         executable: context.package.directory.appending("custom-compile"),
//         // Arguments passed to the executable
//         arguments: [
//             "run", "xcassets",
//             "\(context.package.directory)/Sources/DesignSystem/Resources/Colors.xcassets",
//             "--param", "publicAccess",
//             "--templateName", "swift5",
//             "--output", "\(outputFilePath)"],
//         // Environment variables
//         environment: [:],
//         // Path for the output files
//         outputFilesDirectory: outputPath
//       ),
//     ]
//   }
// }

@main struct CustomCompileCommand: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
  }
}
