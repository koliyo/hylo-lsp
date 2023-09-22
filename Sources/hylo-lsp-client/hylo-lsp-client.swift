import Foundation
import LanguageClient
// import ProcessEnv
import LanguageServerProtocol
import JSONRPC
import UniSocket
import JSONRPC_DataChannel_UniSocket
import JSONRPC_DataChannel_Actor
import ArgumentParser
import Logging
import hylo_lsp

import Core
import FrontEnd
import IR


// Allow loglevel as `ArgumentParser.Option`
extension Logger.Level : ExpressibleByArgument {
}

// let pipePath = "/tmp/my.sock"

struct Options: ParsableArguments {
    // @Flag(help: "Named pipe transport")
    // var pipe: Bool = false

    @Option(help: "Named pipe transport")
    var pipe: String?

    @Option(help: "Log level")
    var log: Logger.Level = Logger.Level.debug

    @Argument(help: "Hylo document filepath")
    var document: String

    func validate() throws {
      let fm = FileManager.default
      var isDirectory: ObjCBool = false

      guard document.hasSuffix(".hylo") else {
        throw ValidationError("document does not have .hylo suffix: \(document)")
      }

      guard fm.fileExists(atPath: document, isDirectory: &isDirectory) else {
        throw ValidationError("document filepath does not exist: \(document)")
      }

      guard !isDirectory.boolValue else {
        throw ValidationError("document filepath is a directory: \(document)")
      }
    }
}

// https://swiftpackageindex.com/apple/swift-argument-parser/1.2.3/documentation/argumentparser/commandsandsubcommands
@main
struct HyloLspCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        abstract: "HyloLSP command line client",
        subcommands: [SemanticToken.self],
        defaultSubcommand: SemanticToken.self)

}

extension HyloLspCommand {
  struct SemanticToken : AsyncParsableCommand {
    @OptionGroup var options: Options

    @Option(help: "Specific row (1-based row counting)")
    var row: Int?

    func validate() throws {
    }

    func run() async throws {
      logger.logLevel = options.log
      // let docURL = URL.init(fileURLWithPath:"hylo/Examples/factorial.hylo")
      // let docURL = URL.init(fileURLWithPath:"hylo/Library/Hylo/Array.hylo")
      let docURL = URL.init(fileURLWithPath: options.document)

      if let pipe = options.pipe {
        print("starting client witn named pipe: \(pipe)")
        let fileManager = FileManager.default

        // Check if file exists
        if fileManager.fileExists(atPath: pipe) {
            // Delete file
            print("delete existing socket: \(pipe)")
            try fileManager.removeItem(atPath: pipe)
        }

        let socket = try UniSocket(type: .local, peer: pipe)
        try socket.bind()
        try socket.listen()
        let client = try socket.accept()
        print("lsp attached")
        client.timeout = (connect: 5, read: nil, write: 5)
        let clientChannel = DataChannel(socket: client)
        await RunHyloClientTests(channel: clientChannel, docURL: docURL)
      }
      else {
        let (clientChannel, serverChannel) = DataChannel.withDataActor()

        Task {
          let server = HyloServer(serverChannel, logger: logger)
          await server.run()
        }

        // await RunHyloClientTests(channel: clientChannel, docURL: docURL)
        let server = try await createServer(channel: clientChannel, docURL: docURL)

        let params = SemanticTokensParams(textDocument: TextDocumentIdentifier(uri: docURL.absoluteString))
        if let tokensData = try await server.semanticTokensFull(params: params) {
          var tokens = tokensData.decode()

          if let row = row {
            tokens = tokens.filter { $0.line+1 == row }
          }

          for t in tokens {
            let type = TokenType(rawValue: t.type)!
            print("line: \(t.line+1), col: \(t.char+1), len: \(t.length), type: \(type), modifiers: \(t.modifiers)")
          }
        }


      }
    }

  }
}
