import Foundation
// import ProcessEnv
// import LanguageServerProtocol
import JSONRPC
// import JSONRPC_DataChannel_StdioPipe
import ArgumentParser
import hylo_lsp
import Logging
import Puppy

#if !os(Windows)
import UniSocket
import JSONRPC_DataChannel_UniSocket
#endif


extension Bool {
    var intValue: Int {
        return self ? 1 : 0
    }
}

// Allow loglevel as `ArgumentParser.Option`
extension Logger.Level: @retroactive ExpressibleByArgument {
}

func forceLineBuffering() {
#if !os(Windows)
  #if os(Linux)
  /**
TODO: Fix this error:
/home/runner/work/hylo-lsp/hylo-lsp/Sources/hylo-lsp-server/hylo-lsp-server-cli.swift:31:11: error: reference to var 'stderr' is not concurrency-safe because it involves shared mutable state
 29 | #if !os(Windows)
 30 |   setvbuf(stdout, nil, _IOLBF, 0)
 31 |   setvbuf(stderr, nil, _IOLBF, 0)
    |           `- error: reference to var 'stderr' is not concurrency-safe because it involves shared mutable state
 32 | #endif
 33 | }
SwiftGlibc.stderr:1:12: note: var declared here
1 | public var stderr: UnsafeMutablePointer<FILE>!
|            `- note: var declared here
*/
  #else
  setvbuf(stdout, nil, _IOLBF, 0)
  setvbuf(stderr, nil, _IOLBF, 0)
  #endif
#endif
}

@main
struct HyloLspCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(commandName: "hylo-lsp-server")

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

    func logHandlerFactory(_ label: String, fileLogger: FileLogger) -> LogHandler {
      if HyloServer.disableLogging {
        return NullLogHandler(label: label)
      }

      var puppy = Puppy()
      puppy.add(fileLogger)

      let puppyHandler = PuppyLogHandler(label: label, puppy: puppy)

      if stdio {
        return puppyHandler
      }

      return MultiplexLogHandler([
        // FileLogHandler(label: label, fileLogger: fileLogger),
        puppyHandler,
        StreamLogHandler.standardOutput(label: label)
      ])
    }

    func run() async throws {
        forceLineBuffering()
        let logFileURL = URL(fileURLWithPath: logFile)
        // let fileLogger = try FileLogging(to: logFileURL)
        let fileLogger = try FileLogger("hylo-lsp",
                    logLevel: puppyLevel(log),
                    fileURL: logFileURL)

        var logger = Logger(label: loggerLabel) { logHandlerFactory($0, fileLogger: fileLogger) }
        logger.logLevel = log

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

          await run(logger: logger, channel: DataChannel.stdioPipe())
        }

        #if !os(Windows)
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
