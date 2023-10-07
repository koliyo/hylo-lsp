import JSONRPC
import LanguageServerProtocol
import LanguageServerProtocol_Server
import Foundation

import Core
import FrontEnd
import IR
import HyloModule
import Logging

enum BuildError : Error {
  case diagnostics(DiagnosticSet)
  case message(String)
}

public class LspState {
  // var ast: AST
  let lsp: JSONRPCServer
  // var program: TypedProgram?
  var documentProvider: DocumentProvider
  // var uri: DocumentUri?

  public init(lsp: JSONRPCServer) {
    // self.ast = ast
    self.lsp = lsp
    self.documentProvider = DocumentProvider()
  }
}


public struct HyloNotificationHandler : NotificationHandler {
  public let lsp: JSONRPCServer
  public let logger: Logger
  var state: LspState
  // var ast: AST { state.ast }
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


  public func textDocumentDidOpen(_ params: TextDocumentDidOpenParams) async {
    // _ = await state.documentProvider.preloadDocument(params.textDocument)
  }

  public func textDocumentDidChange(_ params: TextDocumentDidChangeParams) async {
    // _ = await state.documentProvider.preloadDocument(params.textDocument)
    // TODO: Handle changes from input (not stored on disk)
  }

  public func textDocumentDidClose(_ params: TextDocumentDidCloseParams) async {

  }

  public func textDocumentWillSave(_ params: TextDocumentWillSaveParams) async {

  }

  public func textDocumentDidSave(_ params: TextDocumentDidSaveParams) async {
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


public struct HyloRequestHandler : RequestHandler {
  public let lsp: JSONRPCServer
  public let logger: Logger

  var state: LspState
  // var ast: AST { state.ast }
  // var program: TypedProgram? { state.program }
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
    s.diagnosticProvider = .optionA(DiagnosticOptions(interFileDependencies: false, workspaceDiagnostics: false))

    return s
  }


  public func initialize(_ params: InitializeParams) async -> Result<InitializationResponse, AnyJSONRPCResponseError> {

    // let fm = FileManager.default

    if let rootUri = params.rootUri {
      // guard let path = URL(string: rootUri) else {
      //   return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "invalid rootUri uri format"))
      // }

      // let filepath = path.absoluteURL.path() // URL path to filesystem path
      // logger.debug("filepath: \(filepath)")

      // guard let items = try? fm.contentsOfDirectory(atPath: filepath) else {
      //   return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "could not list rootUri directory: \(path)"))
      // }

      // do {
      //   state.program = try state._buildProgram(items.map { path.appending(path: $0) })
      // }
      // catch {
      //   return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "could not build rootUri directory: \(path), error: \(error)"))
      // }

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

  func locationLink<T>(_ d: T, in ast: AST) -> LocationLink where T: NodeIDProtocol {
    let range = ast[d].site
    let targetUri = range.file.url
    var selectionRange = LSPRange(range)

    if let d = AnyDeclID(d) {
      selectionRange = LSPRange(nameRange(of: d, in: ast) ?? range)
    }

    return LocationLink(targetUri: targetUri.absoluteString, targetRange: LSPRange(range), targetSelectionRange: selectionRange)
  }

  func locationResponse<T>(_ d: T, in ast: AST) -> DefinitionResponse where T: NodeIDProtocol{
    let location = locationLink(d, in: ast)
    return .optionC([location])
  }

  func makeSourcePosition(url: URL, position: Position) -> SourcePosition? {
    guard let f = try? SourceFile(contentsOf: url) else {
      return nil
    }

    return SourcePosition(line: position.line+1, column: position.character+1, in: f)
  }

  public func definition(_ params: TextDocumentPositionParams, _ doc: Document) async -> Result<DefinitionResponse, AnyJSONRPCResponseError> {
    let url = DocumentProvider.resolveDocumentUrl(params.textDocument.uri)
    guard let p = makeSourcePosition(url: url, position: params.position) else {
      return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Invalid document uri: \(params.textDocument.uri)"))
    }

    let (ast, program) = (doc.ast, doc.program)
    logger.debug("Look for symbol definition at position: \(p)")

    guard let id = ast.findNode(p) else {
      logger.warning("Did not find node @ \(p)")
      return .success(nil)
    }

    // logger.debug("found: \(id), in num nodes: \(ast.numNodes)")
    // let s = program.nodeToScope[id]
    let node = ast[id]
    logger.debug("Found node: \(node), id: \(id)")


    if let d = AnyDeclID(id) {
      return .success(locationResponse(d, in: ast))
    }

    if let n = NameExpr.ID(id) {
      // let d = program[n].referredDecl
      let d = program.referredDecl[n]

      if d == nil {
        if let t = program.exprType[n] {

          switch t.base {
          case let u as ProductType:
            return .success(locationResponse(u.decl, in: ast))
          case let u as TypeAliasType:
            return .success(locationResponse(u.decl, in: ast))
          case let u as AssociatedTypeType:
            return .success(locationResponse(u.decl, in: ast))
          case let u as GenericTypeParameterType:
            return .success(locationResponse(u.decl, in: ast))
          case let u as NamespaceType:
            return .success(locationResponse(u.decl, in: ast))
          case let u as TraitType:
            return .success(locationResponse(u.decl, in: ast))
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
      case let .builtinFunction(f):
        logger.warning("builtinFunction: \(f)")
        return .success(nil)
      case .compilerKnownType:
        logger.warning("compilerKnownType: \(d!)")
        return .success(nil)
      case let .member(m, _, _):
        return .success(locationResponse(m, in: ast))
      case let .direct(d, args):
        logger.debug("direct declaration: \(d), generic args: \(args), name: \(program.name(of: d) ?? "__noname__")")
        // let fnNode = ast[d]
        // let range = LSPRange(hylocRange: fnNode.site)
        return .success(locationResponse(d, in: ast))
        // if let fid = FunctionDecl.ID(d) {
        //   let f = sourceModule.functions[Function.ID(fid)]!
        //   logger.debug("Function: \(f)")
        // }
      default:
        logger.warning("Unknown declaration kind: \(d!)")
        break
      }

    }

    logger.warning("Unknown node: \(node)")
    return .success(nil)
  }

  public func definition(_ params: TextDocumentPositionParams) async -> Result<DefinitionResponse, AnyJSONRPCResponseError> {
    await withProgram(params.textDocument) { doc in
      await definition(params, doc)
    }
  }

  public func nameRange(of d: AnyDeclID, in ast: AST) -> SourceRange? {
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
      case BindingDecl.self: return SymbolKind.field
      case VarDecl.self: return SymbolKind.field
      case InitializerDecl.self: return SymbolKind.constructor
      case FunctionDecl.self: return SymbolKind.function
      case SubscriptDecl.self: return SymbolKind.function
      case ProductTypeDecl.self: return SymbolKind.struct
      case ConformanceDecl.self: return SymbolKind.struct
      case TraitDecl.self: return SymbolKind.interface
      default: return SymbolKind.object
    }
  }

  func name(of t: AnyType) -> String {
    switch t.base {
    case let u as ProductType:
      return u.name.value
    case let u as TypeAliasType:
      return u.name.value
    // case let u as ConformanceLensType:
    //   return u.name.value
    case let u as AssociatedTypeType:
      return u.name.value
    case let u as GenericTypeParameterType:
      return u.name.value
    case let u as NamespaceType:
      return u.name.value
    case let u as TraitType:
      return u.name.value
    default:
      logger.warning("Unexpected type: \(t.base)")
      return "unknown"
    }
  }

  public func documentSymbol(_ params: DocumentSymbolParams, _ doc: Document) async -> Result<DocumentSymbolResponse, AnyJSONRPCResponseError> {
    let (ast, program) = (doc.ast, doc.program)
    let symbols = ast.listDocumentSymbols(params.textDocument.uri, program)
    if symbols.isEmpty {
      return .success(nil)
    }

    // TODO: Move symbol lookup to walker
    // TODO: Use lsp child symbols
    var lspSymbols: [DocumentSymbol] = []
    for s in symbols {
      var detail: String? = nil

      if let type = program.declType[s] {
        // detail = program.name(of: type)
        detail = type.description
        // detail = "\(type.base)"
      }

      let decl = ast[s]
      let range = LSPRange(decl.site)
      let selectionRange = LSPRange(nameRange(of: s, in: ast) ?? decl.site)

      switch decl {
      case let d as BindingDecl:
        let p = ast[d.pattern]
        getSymbols(p.subpattern, program: program, ast: ast, symbols: &lspSymbols)
      case _ as SubscriptDecl:
        let name = program.name(of: s) ?? "subscript"
        lspSymbols.append(DocumentSymbol(
          name: name.stem,
          detail: detail,
          kind: kind(s),
          range: range,
          selectionRange: selectionRange
        ))
      case let d as ConformanceDecl:
        let sub = ast[d.subject]
        let name = if let t = program.exprType[d.subject]  { name(of: t) } else { "conformance" }
        lspSymbols.append(DocumentSymbol(
          name: name,
          detail: detail,
          kind: kind(s),
          range: range,
          selectionRange: LSPRange(sub.site)
        ))


      default:
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
          logger.debug("Symbol declaration does not have a name: \(s) @ \(decl.site)")
        }
      }
    }

    // Validate ranges
    lspSymbols = lspSymbols.filter { s in
      if s.selectionRange.start < s.range.start || s.selectionRange.end > s.range.end {
        logger.error("Invalid symbol ranges, selectionRange is outside range: \(s)")
        return false
      }

      return true
    }

    return .success(.optionA(lspSymbols))
  }


  func getSymbols(_ pattern: AnyPatternID, program: TypedProgram, ast: AST, symbols: inout [DocumentSymbol]) {
    let p = ast[pattern]

    switch p {
    case let p as NamePattern:
      let v = ast[p.decl]
        let detail: String? = if let type = program.declType[p.decl] {
          type.description
        }
        else {
          nil
        }

      symbols.append(DocumentSymbol(
        name: v.identifier.value,
        detail: detail,
        kind: SymbolKind.field,
        range: LSPRange(v.site),
        selectionRange: LSPRange(v.identifier.site)
      ))

    case let p as BindingPattern:
      getSymbols(p.subpattern, program: program, ast: ast, symbols: &symbols)
    case let p as TuplePattern:
      for e in p.elements {
        getSymbols(e.pattern, program: program, ast: ast, symbols: &symbols)
      }
    default:
      logger.debug("Unknown pattern: \(p)")
    }
  }

  public func documentSymbol(_ params: DocumentSymbolParams) async -> Result<DocumentSymbolResponse, AnyJSONRPCResponseError> {
    await withProgram(params.textDocument) { doc in
      await documentSymbol(params, doc)
    }
  }

  public func diagnostics(_ params: DocumentDiagnosticParams) async -> Result<DocumentDiagnosticReport, AnyJSONRPCResponseError> {


    let docResult = await state.documentProvider.getDocument(params.textDocument)

    switch docResult {
    case let .success(doc):
      return .success(RelatedDocumentDiagnosticReport(kind: .full, items: []))
    case let .failure(error):
      switch error {
      case let .diagnostics(d):
      let dList = d.elements.map { LanguageServerProtocol.Diagnostic($0) }
      return .success(RelatedDocumentDiagnosticReport(kind: .full, items: dList))
      case let .other(e):
        return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Unknown build error: \(error)"))
      }
    }
  }

  func trySendDiagnostics(_ diagnostics: DiagnosticSet, in uri: DocumentUri) async {
    do {
      logger.debug("[\(uri)] send diagnostics")
      let dList = diagnostics.elements.map { LanguageServerProtocol.Diagnostic($0) }
      let dp = PublishDiagnosticsParams(uri: uri, diagnostics: dList)
      try await lsp.sendNotification(.textDocumentPublishDiagnostics(dp))
    }
    catch {
      logger.error(Logger.Message(stringLiteral: error.localizedDescription))
    }
  }

  func withProgram<ResponseT>(_ textDocument: TextDocumentIdentifier, fn: (Document) async -> Result<ResponseT?, AnyJSONRPCResponseError>) async -> Result<ResponseT?, AnyJSONRPCResponseError> {

    let docResult = await state.documentProvider.getDocument(textDocument)

    switch docResult {
    case let .success(doc):
      return await fn(doc)
    case let .failure(error):
      switch error {
      case let .diagnostics(d):
        logger.warning("Program build failed\n\n\(d)")
        return .success(nil)
      case let .other(e):
        return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Unknown build error: \(error)"))
      }
    }
  }

  // https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide
  // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens
  public func semanticTokensFull(_ params: SemanticTokensParams) async -> Result<SemanticTokensResponse, AnyJSONRPCResponseError> {
    await withProgram(params.textDocument) { doc in
      let (ast, program) = (doc.ast, doc.program)
      let tokens = ast.getSematicTokens(params.textDocument.uri, program)
      logger.debug("[\(params.textDocument.uri)] Return \(tokens.count) semantic tokens")
      return .success(SemanticTokens(tokens: tokens))
    }
  }
}


public actor HyloServer {
  let lsp: JSONRPCServer
  // private var ast: AST
  private var state: LspState
  private let requestHandler: HyloRequestHandler
  private let notificationHandler: HyloNotificationHandler


  public init(_ dataChannel: DataChannel, logger: Logger) {
    lsp = JSONRPCServer(dataChannel)
    let serverInfo = ServerInfo(name: "hylo", version: "0.1.0")
    self.state = LspState(lsp: lsp)
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
    await monitorEvents()
  }

  func monitorEvents() async {
    for await event in await lsp.eventSequence {

			switch event {
			case let .notification(notification):
        await notificationHandler.handleNotification(notification)
			case let .request(request):
        await requestHandler.handleRequest(request)
			case let .error(error):
        logger.debug("LSP stream error: \(error)")
			}
    }
  }
}
