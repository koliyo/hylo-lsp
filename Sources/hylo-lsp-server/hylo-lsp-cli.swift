import Foundation
// import ProcessEnv
import LanguageServerProtocol
import JSONRPC
import UniSocket
import JSONRPC_DataChannel_UniSocket
// import JSONRPC_DataChannel_StdioPipe
import ArgumentParser
import hylo_lsp
import Logging
import FileLogging

extension Bool {
    var intValue: Int {
        return self ? 1 : 0
    }
}

// Allow loglevel as `ArgumentParser.Option`
extension Logger.Level : ExpressibleByArgument {
}


@main
struct HyloLspCommand: AsyncParsableCommand {

    @Option(help: "Log level")
    var log: Logger.Level = Logger.Level.debug

    @Option(help: "Log file")
    var logFile: String = "hylo-lsp.log"

    // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#implementationConsiderations
    // These are VS Code compatible transport flags:

    @Flag(help: "Stdio transport")
    var stdio: Bool = false

    @Option(help: "Named pipe transport")
    var pipe: String?

    @Option(help: "Socket transport")
    var socket: String?

    func validate() throws {
      let numTransports = stdio.intValue + (pipe != nil).intValue + (socket != nil).intValue
      guard numTransports == 1 else {
          throw ValidationError("Exactly one transport method must be defined (stdio, pipe, socket)")
      }
    }

    func run(logger: Logger, channel: DataChannel) async {
      let server = HyloServer(channel, logger: logger)
      await server.run()
    }

    func run() async throws {

        // Force line buffering
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)

        let logFileURL = URL(filePath: logFile)
        let fileLogger = try FileLogging(to: logFileURL)

        // print("Hylo LSP server args: \(CommandLine.arguments)")

        if stdio {
          // For stdio transport it is important that only protocol messages are sent to stdio
          // Only use file backend for logging
          // var logger = try FileLogging.logger(label: loggerLabel, localFile: logFileURL)
          logger = Logger(label: loggerLabel) { label in FileLogHandler(label: label, fileLogger: fileLogger) }
          logger.logLevel = log
          await run(logger: logger, channel: DataChannel.stdioPipe())
        }


        // Multiplexed logging to file and console
        logger = Logger(label: loggerLabel) { label in
          MultiplexLogHandler([
            FileLogHandler(label: label, fileLogger: fileLogger),
            StreamLogHandler.standardOutput(label: loggerLabel)
          ])
        }

        logger.logLevel = log

        if let socket = socket {
          // throw ValidationError("TODO: socket transport: \(socket)")
          let socket = try UniSocket(type: .tcp, peer: socket, timeout: (connect: 5, read: nil, write: 5))
          try socket.attach()
          await run(logger: logger, channel: DataChannel(socket: socket))
        }
        else if let pipe = pipe {
          let socket = try UniSocket(type: .local, peer: pipe, timeout: (connect: 5, read: nil, write: 5))
          try socket.attach()
          await run(logger: logger, channel: DataChannel(socket: socket))
        }
    }
}
