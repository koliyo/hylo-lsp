import JSONRPC
import LanguageServerProtocol
import LanguageServerProtocol_Server
import Foundation

import Core
import FrontEnd
import IR
import HyloModule
import Logging

public class LspState {
  var ast: AST
  let lsp: JSONRPCServer
  var program: TypedProgram?

  public init(ast: AST, lsp: JSONRPCServer) {
    self.ast = ast
    self.lsp = lsp
  }

  var task: Task<TypedProgram, Error>?

  public func buildProgram(_ inputs: [URL]) {
    task = Task {
      return try _buildProgram(inputs)
    }
  }

  public func _buildProgram(_ inputs: [URL]) throws -> TypedProgram {
    // let inputs = files.map { URL.init(fileURLWithPath: $0)}
    let importBuiltinModule = false
    let compileSequentially = false

    var diagnostics = DiagnosticSet()
    logger.debug("buildProgram: \(inputs)")

    _ = try ast.makeModule(HyloNotificationHandler.productName, sourceCode: sourceFiles(in: inputs),
    builtinModuleAccess: importBuiltinModule, diagnostics: &diagnostics)

    let p = try TypedProgram(
    annotating: ScopedProgram(ast), inParallel: !compileSequentially,
    reportingDiagnosticsTo: &diagnostics,
    tracingInferenceIf: nil)
    logger.debug("program is built")
    return p
  }

}

public extension LanguageServerProtocol.LSPRange {
  init(_ range: SourceRange) {
    var (first, last) = (range.first(), range.last()!)
    let incLast = range.file.text.index(after: last.index)
    last = SourcePosition(incLast, in: last.file)

    self.init(start: Position(first), end: Position(last))
  }
}

public extension LanguageServerProtocol.Position {
  init(_ pos: SourcePosition) {
    let (line, column) = pos.lineAndColumn
    self.init(line: line-1, character: column-1)
  }
}


public struct HyloNotificationHandler : NotificationHandler {
  public let lsp: JSONRPCServer
  public let logger: Logger
  var state: LspState
  var ast: AST { state.ast }
  static let productName = "lsp-build"


  private func withErrorLogging(_ fn: () throws -> Void) {
    do {
      try fn()
    }
    catch {
      logger.debug("Error: \(error)")
    }
  }

  private func withErrorLogging(_ fn: () async throws -> Void) async {
    do {
      try await fn()
    }
    catch {
      logger.debug("Error: \(error)")
    }

  }

  public func initialized(_ params: InitializedParams) async {

  }

  public func exit() async {

  }

  func buildDocument(_ uri: DocumentUri) async {
    logger.debug("textDocumentDidOpen: \(uri)")
    // logger.debug("lib uri: \(HyloModule.standardLibrary!.absoluteString)")
    // if uri.commonPrefix(with: HyloModule.standardLibrary!.absoluteString) == HyloModule.standardLibrary!.absoluteString {
    if uri.contains("hyloc/Library/Hylo") {
      // logger.debug("document is lib")
    }
    else {
      // logger.debug("document is not lib")
      let inputs = [URL.init(string: uri)!]
      // let importBuiltinModule = false
      // let compileSequentially = false

      // var diagnostics = DiagnosticSet()

      state.buildProgram(inputs)
      // withErrorLogging {
      //   try state.buildProgram(inputs)
      //   _ = try state.ast.makeModule(HyloNotificationHandler.productName, sourceCode: sourceFiles(in: inputs),
      //   builtinModuleAccess: importBuiltinModule, diagnostics: &diagnostics)

      //   state.program = try TypedProgram(
      //   annotating: ScopedProgram(state.ast), inParallel: !compileSequentially,
      //   reportingDiagnosticsTo: &diagnostics,
      //   tracingInferenceIf: nil)
      // }
    }

  }

  public func textDocumentDidOpen(_ params: TextDocumentDidOpenParams) async {
    await buildDocument(params.textDocument.uri)
  }

  public func textDocumentDidChange(_ params: TextDocumentDidChangeParams) async {
    await buildDocument(params.textDocument.uri)
  }

  public func textDocumentDidClose(_ params: TextDocumentDidCloseParams) async {

  }

  public func textDocumentWillSave(_ params: TextDocumentWillSaveParams) async {

  }

  public func textDocumentDidSave(_ params: TextDocumentDidSaveParams) async {
    await buildDocument(params.textDocument.uri)
  }

  public func protocolCancelRequest(_ params: CancelParams) async {

  }

  public func protocolSetTrace(_ params: SetTraceParams) async {

  }

  public func workspaceDidChangeWatchedFiles(_ params: DidChangeWatchedFilesParams) async {

  }

  public func windowWorkDoneProgressCancel(_ params: WorkDoneProgressCancelParams) async {

  }

  public func workspaceDidChangeWorkspaceFolders(_ params:   DidChangeWorkspaceFoldersParams) async {

  }

  public func workspaceDidChangeConfiguration(_ params: DidChangeConfigurationParams)  async {

  }

  public func workspaceDidCreateFiles(_ params: CreateFilesParams) async {

  }

  public func workspaceDidRenameFiles(_ params: RenameFilesParams) async {

  }

  public func workspaceDidDeleteFiles(_ params: DeleteFilesParams) async {

  }

}

public enum TokenType : UInt32, CaseIterable {
  case type
  case identifier
  case variable
  case function
  case keyword

  var description: String {
      return String(describing: self)
  }
}

public struct HyloRequestHandler : RequestHandler {
  public let lsp: JSONRPCServer
  public let logger: Logger

  var state: LspState
  var ast: AST { state.ast }
  var program: TypedProgram? { state.program }
  // var initTask: Task<TypedProgram, Error>

  private let serverInfo: ServerInfo

  public init(lsp: JSONRPCServer, logger: Logger, serverInfo: ServerInfo, state: LspState) {
    self.lsp = lsp
    self.logger = logger
    self.serverInfo = serverInfo
    self.state = state
  }


  private func getServerCapabilities() -> ServerCapabilities {
    var s = ServerCapabilities()
    let documentSelector = DocumentFilter(pattern: "**/*.hylo")

    // NOTE: Only need to register extensions
    // The protocol defines a set of token types and modifiers but clients are allowed to extend these and announce the values they support in the corresponding client capability.
    // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens
    let tokenLedgend = SemanticTokensLegend(tokenTypes: TokenType.allCases.map { $0.description }, tokenModifiers: ["private", "public"])

    s.textDocumentSync = .optionA(TextDocumentSyncOptions(openClose: false, change: TextDocumentSyncKind.full, willSave: false, willSaveWaitUntil: false, save: nil))
    s.textDocumentSync = .optionB(TextDocumentSyncKind.full)
    s.definitionProvider = .optionA(true)
    // s.typeDefinitionProvider = .optionA(true)
    s.documentSymbolProvider = .optionA(true)
    // s.semanticTokensProvider = .optionA(SemanticTokensOptions(legend: tokenLedgend, range: .optionA(true), full: .optionA(true)))
    s.semanticTokensProvider = .optionB(SemanticTokensRegistrationOptions(documentSelector: [documentSelector], legend: tokenLedgend, range: .optionA(false), full: .optionA(true)))

    return s
  }


  public func initialize(_ params: InitializeParams) async -> Result<InitializationResponse, AnyJSONRPCResponseError> {
    let fm = FileManager.default

    if let rootUri = params.rootUri {
      guard let path = URL(string: rootUri) else {
        return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "invalid rootUri uri format"))
      }

      let filepath = path.absoluteURL.path() // URL path to filesystem path
      logger.debug("filepath: \(filepath)")

      guard let items = try? fm.contentsOfDirectory(atPath: filepath) else {
        return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "could not list rootUri directory: \(path)"))
      }

      do {
        state.program = try state._buildProgram(items.map { path.appending(path: $0) })
      }
      catch {
        return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "could not build rootUri directory: \(path), error: \(error)"))
      }

      return .success(InitializationResponse(capabilities: getServerCapabilities(), serverInfo: serverInfo))
    }
    else {
      // return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "expected rootUri parameter"))

      logger.debug("init without rootUri")
      return .success(InitializationResponse(capabilities: getServerCapabilities(), serverInfo: serverInfo))
    }
  }

  public func shutdown() async {

  }

  public func definition(_ params: TextDocumentPositionParams) async -> Result<DefinitionResponse, AnyJSONRPCResponseError> {
    guard let task = state.task else {
      return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Expected an opened document"))
    }

    guard let program = try? await task.value else {
      return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Compilation missing"))
    }

    let url = URL.init(string: params.textDocument.uri)!
    guard let f = try? SourceFile(contentsOf: url) else {
      return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Invalid document uri"))
    }

    let pos = params.position

    let p = SourcePosition(line: pos.line+1, column: pos.character+1, in: f)
    logger.debug("Look for symbol definition at position: \(p)")

    if let id = ast.findNode(p) {
      // logger.debug("found: \(id), in num nodes: \(ast.numNodes)")
      // let s = program.nodeToScope[id]
      let node = ast[id]
      logger.debug("Found node: \(node), id: \(id)")

      let locationFromDecl = { (d: AnyDeclID) in
        let range = ast[d].site
        let selectionRange = LSPRange(nameRange(of: d) ?? range)
        return LocationLink(targetUri: url.absoluteString, targetRange: LSPRange(range), targetSelectionRange: selectionRange)
      }

      let locationResponseFromDecl = { (d: AnyDeclID) -> DefinitionResponse in
        let location = locationFromDecl(d)
        return .optionC([location])
      }

      if let d = AnyDeclID(id) {
        return .success(locationResponseFromDecl(d))
      }

      if let n = NameExpr.ID(id) {
        // let d = program[n].referredDecl
        let d = program.referredDecl[n]

        if d == nil {
          if let t = program.exprType[n] {

            switch t.base {
            case let u as ProductType:
              return .success(locationResponseFromDecl(AnyDeclID(u.decl)))
            case let u as TypeAliasType:
              return .success(locationResponseFromDecl(AnyDeclID(u.decl)))
            case let u as AssociatedTypeType:
              return .success(locationResponseFromDecl(AnyDeclID(u.decl)))
            case let u as GenericTypeParameterType:
              return .success(locationResponseFromDecl(AnyDeclID(u.decl)))
            case let u as NamespaceType:
              return .success(locationResponseFromDecl(AnyDeclID(u.decl)))
            case let u as TraitType:
              return .success(locationResponseFromDecl(AnyDeclID(u.decl)))
            default:
              fatalError("not implemented")
            }
          }

          if let x = AnyPatternID(id) {
            logger.debug("pattern: \(x)")
          }

          if let s = program.nodeToScope[id] {
            logger.debug("scope: \(s)")
            if let decls = program.scopeToDecls[s] {
              for d in decls {
                  if let t = program.declType[d] {
                    logger.debug("decl: \(d), type: \(t)")
                  }
              }
            }


            if let fn = ast[s] as? FunctionDecl {
              logger.debug("TODO: Need to figure out how to get resolved return type of function signature: \(fn.site)")
              return .success(nil)
              // return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO: Need to figure out how to get resolved return type of function signature: \(fn.site)"))
            }
          }

          // return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Internal error, must be able to resolve declaration"))
          await logInternalError("Internal error, must be able to resolve declaration")
          return .success(nil)
        }

        switch d {
        case let .constructor(d, _):
          let initializer = ast[d]
          let range = ast[d].site
          let selectionRange = LSPRange(initializer.introducer.site)
          let response = LocationLink(targetUri: url.absoluteString, targetRange: LSPRange(range), targetSelectionRange: selectionRange)
          return .success(.optionC([response]))
        case let .direct(d, args):
          logger.debug("d: \(d), generic args: \(args), name: \(program.name(of: d) ?? "__noname__")")
          // let fnNode = ast[d]
          // let range = LSPRange(hylocRange: fnNode.site)
          return .success(locationResponseFromDecl(d))
          // if let fid = FunctionDecl.ID(d) {
          //   let f = sourceModule.functions[Function.ID(fid)]!
          //   logger.debug("Function: \(f)")
          // }
        default:
          await logInternalError("Unknown declaration kind: \(d!)")
        }

      }

    }

    return .success(nil)
  }

  public func nameRange(of d: AnyDeclID) -> SourceRange? {
    // if let e = self.ast[d] as? SingleEntityDecl { return Name(stem: e.baseName) }

    switch d.kind {
    case FunctionDecl.self:
      return ast[FunctionDecl.ID(d)!].identifier!.site
    case InitializerDecl.self:
      return ast[InitializerDecl.ID(d)!].site
    case MethodImpl.self:
      return ast[MethodDecl.ID(d)!].identifier.site
    case SubscriptImpl.self:
      return ast[SubscriptDecl.ID(d)!].site
    case VarDecl.self:
      return ast[VarDecl.ID(d)!].identifier.site
    case ParameterDecl.self:
      return ast[ParameterDecl.ID(d)!].identifier.site
    default:
      return nil
    }
  }

  func kind(_ id: AnyDeclID) -> SymbolKind {
    switch id.kind {
      case VarDecl.self: return SymbolKind.field
      case FunctionDecl.self: return SymbolKind.function
      case ProductTypeDecl.self: return SymbolKind.struct
      default: return SymbolKind.object
    }
  }

  public func documentSymbol(_ params: DocumentSymbolParams) async -> Result<DocumentSymbolResponse, AnyJSONRPCResponseError> {
    guard let task = state.task else {
      return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Expected an opened document"))
    }

    do {
      let program = try await task.value
      let symbols = ast.listSymbols(params.textDocument.uri)
      var lspSymbols: [DocumentSymbol] = []
      for s in symbols {
        var detail: String? = nil

        if let type = program.declType[s] {
          // detail = program.name(of: type)
          detail = type.description
          // detail = "\(type.base)"
        }

        let declRange = ast[s].site
        let range = LSPRange(declRange)
        let selectionRange = LSPRange(nameRange(of: s) ?? declRange)

        if let name = program.name(of: s) {
          lspSymbols.append(DocumentSymbol(
            name: name.stem,
            detail: detail,
            kind: kind(s),
            range: range,
            selectionRange: selectionRange
          ))
        }
        else {
          logger.debug("Symbol declaration does not have a name: \(s)")
        }
      }

      return .success(.optionA(lspSymbols))
    }
    catch {
      await logInternalError("Error during symbol resolution: \(error)")
      return .success(nil)
    }
  }

  // https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide
  // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens
  public func semanticTokensFull(_ params: SemanticTokensParams) async -> Result<SemanticTokensResponse, AnyJSONRPCResponseError> {
    guard let _ = state.task else {
      return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Expected an opened document"))
    }


    let tokens = ast.getSematicTokens(params.textDocument.uri)
    return .success(SemanticTokens(tokens: tokens))
  }

}


public actor HyloServer {
  let lsp: JSONRPCServer
  // private var ast: AST
  private var state: LspState
  private let requestHandler: HyloRequestHandler
  private let notificationHandler: HyloNotificationHandler


  public init(_ dataChannel: DataChannel, logger: Logger, useStandardLibrary: Bool = true) {
    lsp = JSONRPCServer(dataChannel)
    let serverInfo = ServerInfo(name: "hylo", version: "0.1.0")
    let ast = useStandardLibrary ? AST.standardLibrary : AST.coreModule
    self.state = LspState(ast: ast, lsp: lsp)
    requestHandler = HyloRequestHandler(lsp: lsp, logger: logger, serverInfo: serverInfo, state: state)
    notificationHandler = HyloNotificationHandler(lsp: lsp, logger: logger, state: state)

    // Task {
		// 	await monitorRequests()
		// }

    // Task {
		// 	await monitorNotifications()
		// }
  }

  public func run() async {
    logger.debug("starting server")
    async let t1: () = monitorRequests()
    async let t2: () = monitorNotifications()
    async let t3: () = monitorErrors()

    // do {
    //   // try await lsp.sendNotification(.windowShowMessage(ShowMessageParams(type: .warning, message: "foo")))
    //   try await lsp.sendNotification(.windowLogMessage(LogMessageParams(type: .warning, message: "foo")))
    // }
    // catch {
    //   logger.debug("error: \(error)")
    // }

    _ = await [t1, t2, t3]
  }

  func monitorErrors() async {
    for await error in await lsp.errorSequence {
      logger.debug("LSP stream error: \(error)")
    }
  }

  func monitorRequests() async {
    for await request in await lsp.requestSequence {
      await requestHandler.handleRequest(request)
    }
  }

  func monitorNotifications() async {
    for await notification in await lsp.notificationSequence {
      await notificationHandler.handleNotification(notification)
    }
  }
}
