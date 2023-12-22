import Foundation
import LanguageClient
// import ProcessEnv
import LanguageServerProtocol
import LSPClient
import JSONRPC
#if !os(Windows)
import UniSocket
import JSONRPC_DataChannel_UniSocket
#endif
import ArgumentParser
import Logging
import hylo_lsp
import Puppy
import SwiftLogConsoleColors

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

    @Option(help: "Log level")
    var log: Logger.Level = Logger.Level.debug

    @Argument(help: "Hylo document filepath")
    var documents: [String]

    public static func parseDocument(_ docLocation: String) throws -> DocumentLocation {

      #if os(Windows)
      // let search1 = try Regex(#"(.+)(?::(\d+)(?:\.(\d+))?)"#)
      print("Document path parsing not currently supported on Windows, assuming normal filepath")
      let path = docLocation
      let url = resolveDocumentUrl(path)
      let uri = url.absoluteString
      return DocumentLocation(filepath: path, url: url, uri: uri, line: nil, char: nil)
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

      var line: UInt?
      var char: UInt?
      var path = docLocation

      if let result = try search1.wholeMatch(in: path) {
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

    static func validate(_ docLocation: String) throws {
      let d = try parseDocument(docLocation)

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

    func validate() throws {
      for d in documents {
        try Options.validate(d)
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

func initServer(workspace: String? = nil, documents: [URL], openDocuments: Bool, logger: Logger) async throws -> RestartingServer<
  JSONRPCServerConnection
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
  return try await createServer(channel: clientChannel, workspace: workspace, documents: documents, openDocuments: openDocuments)
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

func printDiagnostic(_ d: LanguageServerProtocol.Diagnostic, in filepath: String) {
  print("\(cliLink(uri: filepath, range: d.range)) \(d.severity ?? .information): \(d.message)")
  for ri in d.relatedInformation ?? [] {
    print("  \(cliLink(uri: ri.location.uri, range: ri.location.range)) \(ri.message)")
  }
}

func withDiagnosticsCheck<T>(_ fn: () async throws -> T) async throws -> T {
  do {
    return try await fn()
  }
  catch let d as DiagnosticSet {

    for d in d.elements {
      let _d = LanguageServerProtocol.Diagnostic(d)
      printDiagnostic(_d, in: d.site.file.url.path)
    }

    throw d
  }
}

protocol DocumentCommand : AsyncParsableCommand {
  func process(doc: DocumentLocation, using server: ServerConnection) async throws
}

extension DocumentCommand {

  func logHandlerFactory(_ label: String) -> LogHandler {
    if HyloServer.disableLogging {
      return NullLogHandler(label: label)
    }

    return ColorStreamLogHandler.standardOutput(label: label, logIconType: .rainbow)
  }

  func makeLogger(_ options: Options) -> Logger {
    var logger = Logger(label: loggerLabel) { logHandlerFactory($0) }
    logger.logLevel = options.log
    return logger
  }

  func processDocuments(_ docs: [String], openDocuments: Bool = true, logger: Logger) async throws {
    let docs = try docs.map { try Options.parseDocument($0) }

    let docUrls = docs.map { $0.url }
    let server = try await initServer(documents: docUrls, openDocuments: false, logger: logger)

    for doc in docs {
      let td = try textDocument(doc.url)
      let docParams = DidOpenTextDocumentParams(textDocument: td)
      try await server.textDocumentDidOpen(params: docParams)
      try await self.process(doc: doc, using: server)
    }
  }

}


extension HyloLspCommand {
  struct Symbols : DocumentCommand {
    @OptionGroup var options: Options

    func process(doc: DocumentLocation, using server: ServerConnection) async throws {

      let params = DocumentSymbolParams(textDocument: TextDocumentIdentifier(uri: doc.uri))

      let response = try await server.documentSymbol(params: params)

      switch response {
        case nil:
          print("No symbols")
        case let .optionA(symbols):
          if symbols.isEmpty {
            print("No symbols")
          }
          for s in symbols {
            printSymbol(s, in: doc)
          }
        case let .optionB(s):
          if s.isEmpty {
            print("No symbols")
          }
          for s in s {
            printSymbol(documentSymbol(s), in: doc)
          }
      }
    }



    func run() async throws {
      try await processDocuments(options.documents, logger: makeLogger(options))
    }

    func documentSymbol(_ s: SymbolInformation) -> DocumentSymbol {
      DocumentSymbol(name: s.name, kind: s.kind, range: s.location.range, selectionRange: s.location.range)
    }

    func matchLocation(symbol: DocumentSymbol, doc: DocumentLocation) -> Bool {
      guard var line = doc.line else {
        return true
      }

      line = line - 1
      let r = symbol.selectionRange
      return r.start.line <= line && r.end.line >= line
    }

    func printSymbol(_ s: DocumentSymbol, in doc: DocumentLocation, indent: String = "") {
      if matchLocation(symbol: s, doc: doc) {
        print("\(cliLink(uri: doc.uri, range: s.range))\(indent) name: \(s.name), kind: \(s.kind), selection: \(s.selectionRange)")
      }

      for c in s.children ?? [] {
        printSymbol(c, in: doc, indent: indent + "  ")
      }
    }
  }

  struct Definition : DocumentCommand {
    @OptionGroup var options: Options

    func process(doc: DocumentLocation, using server: ServerConnection) async throws {

      guard let pos = doc.position() else {
        throw ValidationError("Invalid position")
      }

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

    func run() async throws {
      try await processDocuments(options.documents, logger: makeLogger(options))
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

  struct Diagnostics : DocumentCommand {
    @OptionGroup var options: Options

    func process(doc: DocumentLocation, using server: ServerConnection) async throws {
      let params = DocumentDiagnosticParams(textDocument: TextDocumentIdentifier(uri: doc.uri))
      let report = try await server.diagnostics(params: params)
      for d in report.items ?? [] {
        printDiagnostic(d, in: doc.filepath)
      }

      for (f, r) in report.relatedDocuments ?? [:] {
        for d in r.items ?? [] {
          printDiagnostic(d, in: f)
        }
      }
    }

    func run() async throws {
      try await processDocuments(options.documents, logger: makeLogger(options))
    }

  }

  struct SemanticToken : DocumentCommand {
    @OptionGroup var options: Options

    // @Option(help: "Specific row (1-based row counting)")
    // var row: Int?

    func validate() throws {
    }

    func process(doc: DocumentLocation, using server: ServerConnection) async throws {

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

    func run() async throws {
      try await processDocuments(options.documents, logger: makeLogger(options))
    }
  }

  struct Pipe : AsyncParsableCommand {
    @Argument(help: "Pipe filepath")
    var pipeFilepath: String

    func run() async throws {
      #if !os(Windows)
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
      print("LSP server attached")
      client.timeout = (connect: 5, read: nil, write: 5)
      let clientChannel = DataChannel(socket: client)

      let fm = FileManager.default
      let workspace = URL.init(fileURLWithPath: fm.currentDirectoryPath)
      let server = try await createServer(channel: clientChannel, workspace: workspace, documents: [])

      let td = try textDocument(URL.init(fileURLWithPath: "hylo/Examples/factorial.hylo"))
      let docParams = DidOpenTextDocumentParams(textDocument: td)
      try await server.textDocumentDidOpen(params: docParams)

      try await server.setTrace(params: SetTraceParams(value: .off))
      print("traced")
      try await server.shutdownAndExit()
      print("Sent shutdown")
      // client.timeout = (connect: 5, read: nil, write: 5)
      // let clientChannel = DataChannel(socket: client)
      // await RunHyloClientTests(channel: clientChannel, docURL: docURL)
      #endif
    }
  }
}
