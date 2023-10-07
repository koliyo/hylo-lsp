// import ProcessEnv
import LanguageServerProtocol
import JSONRPC
// import JSONRPC_DataChannel_StdioPipe
import ArgumentParser
import hylo_lsp
import Logging
import Puppy

#if !os(Windows)
import Foundation
import UniSocket
import JSONRPC_DataChannel_UniSocket
#endif


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

    func puppyLevel(_ level: Logger.Level) -> LogLevel {
      // LogLevel(rawValue: level.rawValue)
      switch level {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .warning: .warning
        case .error: .error
        case .critical: .critical
      }
    }

    func run() async throws {

        #if !os(Windows)
        // Force line buffering
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)
        #endif

        let logFileURL = URL(fileURLWithPath: logFile)
        // let fileLogger = try FileLogging(to: logFileURL)
        let fileLogger = try FileLogger("hylo-lsp",
                    logLevel: puppyLevel(log),
                    fileURL: logFileURL)
        var puppy = Puppy()
        puppy.add(fileLogger)

        // print("Hylo LSP server args: \(CommandLine.arguments)")

        if stdio {
          // For stdio transport it is important that only protocol messages are sent to stdio
          // Only use file backend for logging
          // var logger = try FileLogging.logger(label: loggerLabel, localFile: logFileURL)
          // logger = Logger(label: loggerLabel) { label in FileLogHandler(label: lebel, fileLogger: fileLogger) }



          // LoggingSystem.bootstrap {
          //     var handler = PuppyLogHandler(label: $0, puppy: puppy)
          //     // Set the logging level.
          //     handler.logLevel = log
          //     return handler
          // }

          logger = Logger(label: loggerLabel) { label in
            PuppyLogHandler(label: label, puppy: puppy)
          }

          logger.logLevel = log
          await run(logger: logger, channel: DataChannel.stdioPipe())
        }



        // Multiplexed logging to file and console
        logger = Logger(label: loggerLabel) { label in
          MultiplexLogHandler([
            // FileLogHandler(label: label, fileLogger: fileLogger),
            PuppyLogHandler(label: label, puppy: puppy),
            StreamLogHandler.standardOutput(label: label)
          ])
        }

        logger.logLevel = log

        #if os(Windows)
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
        #else
        if let _ = socket {
          fatalError("socket mode not supported");
        }
        else if let _ = pipe {
          fatalError("pipe mode not supported");
        }
        #endif
    }
}
