import Foundation
import LanguageClient
// import ProcessEnv
import LanguageServerProtocol
import LanguageServerProtocol_Client
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

    public func parseDocument() throws -> (path: String, line: UInt?, char: UInt?) {

      let search1 = #/(.+)(?::(\d+)(?:\.(\d+))?)/#

      var path = document
      var line: UInt?
      var char: UInt?

      if let result = try? search1.wholeMatch(in: document) {
        path = String(result.1)
        guard let l = UInt(result.2) else {
          throw ValidationError("Invalid document line number: \(result.2)")
        }

        line = l

        if let c = result.3 {
          guard let c = UInt(c) else {
            throw ValidationError("Invalid document char number: \(result.2)")
          }

          char = c
        }
      }

      return (String(path), line, char)
    }

    func validate() throws {
      let (path, _, _) = try parseDocument()

      let fm = FileManager.default
      var isDirectory: ObjCBool = false

      guard path.hasSuffix(".hylo") else {
        throw ValidationError("document does not have .hylo suffix: \(path)")
      }

      guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else {
        throw ValidationError("document filepath does not exist: \(path)")
      }

      guard !isDirectory.boolValue else {
        throw ValidationError("document filepath is a directory: \(path)")
      }

    }
}

// https://swiftpackageindex.com/apple/swift-argument-parser/1.2.3/documentation/argumentparser/commandsandsubcommands
@main
struct HyloLspCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        abstract: "HyloLSP command line client",
        subcommands: [
          SemanticToken.self,
          Diagnostics.self,
          Definition.self,
        ],
        defaultSubcommand: nil)
}

extension DocumentUri {
}

public func cliLink(uri: String, range: LSPRange) -> String {
  "\(uri):\(range.start.line+1):\(range.start.character+1)"
}

func initServer(workspace: String? = nil, documents: [String]) async throws -> RestartingServer<
  JSONRPCServer
> {
  let fm = FileManager.default
  let workspace = URL.init(fileURLWithPath: workspace ?? fm.currentDirectoryPath)

  let docUrls = documents.map { URL.init(fileURLWithPath: $0) }

  let (clientChannel, serverChannel) = DataChannel.withDataActor()

  // Run the LSP Server in a background task
  Task {
    let server = HyloServer(serverChannel, logger: logger)
    await server.run()
  }

  // Return the RPC server (client side)
  return try await createServer(channel: clientChannel, workspace: workspace, documents: docUrls)
}

extension HyloLspCommand {

  struct Definition : AsyncParsableCommand {
    @OptionGroup var options: Options
    func run() async throws {
      logger.logLevel = options.log
      let (doc, line, char) = try options.parseDocument()

      guard let line = line else {
        throw ValidationError("Invalid position")
      }

      guard let char = char else {
        throw ValidationError("Invalid position")
      }

      let pos = Position(line: Int(line-1), character: Int(char-1))

      let server = try await initServer(documents: [doc])
      let params = TextDocumentPositionParams(uri: doc, position: pos)

      let definition = try await server.definition(params: params)

      switch definition {
        case nil:
          print("No definition")
        case let .optionA(l):
          printLocation(l)
        case let .optionB(l):
          for l in l {
            printLocation(l)
          }
        case let .optionC(l):
          for l in l {
            printLocation(l)
          }
      }
    }

    func locationLink(_ l: Location) -> LocationLink {
      LocationLink(targetUri: l.uri, targetRange: l.range, targetSelectionRange: LSPRange(start: Position.zero, end: Position.zero))
    }

    func printLocation(_ l: Location) {
      printLocation(locationLink(l))
    }

    func printLocation(_ l: LocationLink) {
      print("\(cliLink(uri: l.targetUri, range: l.targetRange))")
    }
  }

  struct Diagnostics : AsyncParsableCommand {
    @OptionGroup var options: Options
    func run() async throws {
      logger.logLevel = options.log
      let (doc, line, _) = try options.parseDocument()
      let docURL = URL.init(fileURLWithPath: doc)
      let server = try await initServer(documents: [doc])

      let params = DocumentDiagnosticParams(textDocument: TextDocumentIdentifier(uri: docURL.absoluteString))
      let report = try await server.diagnostics(params: params)
      for i in report.items ?? [] {
        print("\(cliLink(uri: docURL.path, range: i.range)) \(i.severity ?? .information): \(i.message)")
        for ri in i.relatedInformation ?? [] {
          print("  \(cliLink(uri: ri.location.uri, range: ri.location.range)) \(ri.message)")
        }
      }
    }

  }

  struct SemanticToken : AsyncParsableCommand {
    @OptionGroup var options: Options

    // @Option(help: "Specific row (1-based row counting)")
    // var row: Int?

    func validate() throws {
    }

    func run() async throws {
      logger.logLevel = options.log
      // let docURL = URL.init(fileURLWithPath:"hylo/Examples/factorial.hylo")
      // let docURL = URL.init(fileURLWithPath:"hylo/Library/Hylo/Array.hylo")
      // let docURL = URL.init(fileURLWithPath: options.document)
      let (doc, line, _) = try options.parseDocument()
      let docURL = URL.init(fileURLWithPath: doc)
      let workspace = docURL.deletingLastPathComponent()

      if let pipe = options.pipe {
        print("starting client witn named pipe: \(pipe)")
        // let fileManager = FileManager.default

        // // Check if file exists
        // if fileManager.fileExists(atPath: pipe) {
        //     // Delete file
        //     print("delete existing socket: \(pipe)")
        //     try fileManager.removeItem(atPath: pipe)
        // }

        // let socket = try UniSocket(type: .local, peer: pipe)
        // try socket.bind()
        // try socket.listen()
        // let client = try socket.accept()
        // print("lsp attached")
        // client.timeout = (connect: 5, read: nil, write: 5)
        // let clientChannel = DataChannel(socket: client)
        // await RunHyloClientTests(channel: clientChannel, docURL: docURL)
      }
      else {

        let server = try await initServer(documents: [doc])
        let params = SemanticTokensParams(textDocument: TextDocumentIdentifier(uri: docURL.absoluteString))
        if let tokensData = try await server.semanticTokensFull(params: params) {
          var tokens = tokensData.decode()

          if let line = line {
            tokens = tokens.filter { $0.line+1 == line }
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
