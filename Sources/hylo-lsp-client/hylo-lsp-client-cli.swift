import Foundation
import LanguageClient
// import ProcessEnv
import LanguageServerProtocol
import LanguageServerProtocol_Client
import JSONRPC
#if !os(Windows)
import UniSocket
import JSONRPC_DataChannel_UniSocket
#endif
import ArgumentParser
import Logging
import hylo_lsp

import Core
import FrontEnd

#if !os(Windows)
import RegexBuilder
#endif

// Allow loglevel as `ArgumentParser.Option`
extension Logger.Level : ExpressibleByArgument {
}

// let pipePath = "/tmp/my.sock"

struct DocumentLocation {
  public let filepath: String
  public let url: URL
  public let uri: DocumentUri
  public let line: UInt?
  public let char: UInt?

  public func position() -> Position? {
    guard let line = line else { return nil }
    guard let char = char else { return nil }
    guard line > 0 && char > 0 else { return nil }

    return Position(line: Int(line-1), character: Int(char-1))
  }
}

struct Options: ParsableArguments {
    // @Flag(help: "Named pipe transport")
    // var pipe: Bool = false

    @Option(help: "Named pipe transport")
    var pipe: String?

    @Option(help: "Log level")
    var log: Logger.Level = Logger.Level.debug

    @Argument(help: "Hylo document filepath")
    var document: String

    public func parseDocument() throws -> DocumentLocation {

      #if os(Windows)
      // let search1 = try Regex(#"(.+)(?::(\d+)(?:\.(\d+))?)"#)
      logger.warning("Document path parsing not currently supported on Windows, assuming normal filepath")
      let url = resolveDocumentUrl(document)
      let uri = url.absoluteString
      return DocumentLocation(filepath: document, url: url, uri: uri, line: nil, char: nil)
      #else
      // NOTE: Can not use regex literal, it messes with the conditional windows compilation somehow...
      // let search1 = #/(.+)(?::(\d+)(?:\.(\d+))?)/#
      let search1 = Regex {
        Capture {
          OneOrMore(.any)
        }
        Regex {
          ":"
          Capture {
            OneOrMore(.digit)
          }
          Optionally {
            Regex {
              "."
              Capture {
                OneOrMore(.digit)
              }
            }
          }
        }
      }

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

      // Resolve proper uri
      let url = resolveDocumentUrl(path)
      let uri = url.absoluteString

      return DocumentLocation(filepath: path, url: url, uri: uri, line: line, char: char)
      #endif
    }

    func validate() throws {
      let d = try parseDocument()

      let fm = FileManager.default
      var isDirectory: ObjCBool = false

      guard d.filepath.hasSuffix(".hylo") else {
        throw ValidationError("document does not have .hylo suffix: \(d.filepath)")
      }

      guard fm.fileExists(atPath: d.filepath, isDirectory: &isDirectory) else {
        throw ValidationError("document filepath does not exist: \(d.filepath)")
      }

      guard !isDirectory.boolValue else {
        throw ValidationError("document filepath is a directory: \(d.filepath)")
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
          Symbols.self,
          Pipe.self,
        ],
        defaultSubcommand: nil)
}

extension DocumentUri {
}

public func cliLink(uri: String, range: LSPRange) -> String {
  "\(uri):\(range.start.line+1):\(range.start.character+1)"
}

func initServer(workspace: String? = nil, documents: [URL]) async throws -> RestartingServer<
  JSONRPCServer
> {
  let fm = FileManager.default
  let workspace = URL.init(fileURLWithPath: workspace ?? fm.currentDirectoryPath)

  // let documents = documents.map { URL.init(fileURLWithPath: $0) }

  let (clientChannel, serverChannel) = DataChannel.withDataActor()

  // Run the LSP Server in a background task
  Task {
    let server = HyloServer(serverChannel, logger: logger)
    await server.run()
  }

  // Return the RPC server (client side)
  return try await createServer(channel: clientChannel, workspace: workspace, documents: documents)
}

func resolveDocumentUrl(_ uri: String) -> URL {

  // Check if fully qualified url
  if let url = URL(string: uri) {
    if url.scheme != nil {
      return url
    }
  }

  let s = uri as NSString

  // Check if absoult path
  if s.isAbsolutePath {
    return URL(fileURLWithPath: uri)
  }
  else {
    let fm = FileManager.default
    let p = NSString.path(withComponents: [fm.currentDirectoryPath, uri])
    return URL(fileURLWithPath: p)
  }
}

func resolveDocumentUri(_ uri: String) -> DocumentUri {
  return resolveDocumentUrl(uri).absoluteString
}

extension HyloLspCommand {
  struct Symbols : AsyncParsableCommand {
    @OptionGroup var options: Options
    func run() async throws {
      logger.logLevel = options.log
      let doc = try options.parseDocument()

      let server = try await initServer(documents: [doc.url])
      let params = DocumentSymbolParams(textDocument: TextDocumentIdentifier(uri: doc.uri))

      let symbols = try await server.documentSymbol(params: params)

      switch symbols {
        case nil:
          print("No symbols")
        case let .optionA(s):
          if s.isEmpty {
            print("No symbols")
          }
          for s in s {
            printSymbol(s, in: doc.filepath)
          }
        case let .optionB(s):
          if s.isEmpty {
            print("No symbols")
          }
          for s in s {
            printSymbol(documentSymbol(s), in: doc.filepath)
          }
      }
    }

    func documentSymbol(_ s: SymbolInformation) -> DocumentSymbol {
      DocumentSymbol(name: s.name, kind: s.kind, range: s.location.range, selectionRange: s.location.range)
    }

    func printSymbol(_ s: DocumentSymbol, in uri: DocumentUri, indent: String = "") {
      print("\(cliLink(uri: uri, range: s.range))\(indent) name: \(s.name), kind: \(s.kind), selection: \(s.selectionRange)")
      for c in s.children ?? [] {
        printSymbol(c, in: uri, indent: indent + "  ")
      }
    }
  }

  struct Definition : AsyncParsableCommand {
    @OptionGroup var options: Options
    func run() async throws {
      logger.logLevel = options.log
      let doc = try options.parseDocument()

      guard let pos = doc.position() else {
        throw ValidationError("Invalid position")
      }

      let server = try await initServer(documents: [doc.url])
      let params = TextDocumentPositionParams(uri: doc.uri, position: pos)

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
      let doc = try options.parseDocument()
      let server = try await initServer(documents: [doc.url])

      let params = DocumentDiagnosticParams(textDocument: TextDocumentIdentifier(uri: doc.uri))
      let report = try await server.diagnostics(params: params)
      for i in report.items ?? [] {
        print("\(cliLink(uri: doc.filepath, range: i.range)) \(i.severity ?? .information): \(i.message)")
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
      let doc = try options.parseDocument()
      // let workspace = docURL.deletingLastPathComponent()

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

        let server = try await initServer(documents: [doc.url])
        let params = SemanticTokensParams(textDocument: TextDocumentIdentifier(uri: doc.uri))
        if let tokensData = try await server.semanticTokensFull(params: params) {
          var tokens = tokensData.decode()

          if let line = doc.line {
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

  struct Pipe : AsyncParsableCommand {
    @Argument(help: "Pipe filepath")
    var pipeFilepath: String

    func run() async throws {
      let pipe = pipeFilepath

      let fileManager = FileManager.default

      // Check if file exists
      if fileManager.fileExists(atPath: pipe) {
          // Delete file
          print("Delete existing socket: \(pipe)")
          try fileManager.removeItem(atPath: pipe)
      }

      let socket = try UniSocket(type: .local, peer: pipe)
      try socket.bind()
      try socket.listen()
      print("Created socket pipe: \(pipe)")
      let client = try socket.accept()
      print("LSP attached")
      // client.timeout = (connect: 5, read: nil, write: 5)
      // let clientChannel = DataChannel(socket: client)
      // await RunHyloClientTests(channel: clientChannel, docURL: docURL)
    }

  }

}
