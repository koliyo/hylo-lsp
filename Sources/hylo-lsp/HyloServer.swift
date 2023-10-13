import JSONRPC
import LanguageServerProtocol
import LanguageServerProtocol_Server
import Foundation

import Core
import FrontEnd
import HyloModule
import Logging

enum BuildError : Error {
  case diagnostics(DiagnosticSet)
  case message(String)
}


public struct HyloNotificationHandler : NotificationHandler {
  public let lsp: JSONRPCServer
  public let logger: Logger
  var state: ServerState
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

  public func workspaceDidChangeWorkspaceFolders(_ params: DidChangeWorkspaceFoldersParams) async {
    await state.workspaceDidChangeWorkspaceFolders(params)
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

  var state: ServerState
  // var ast: AST { state.ast }
  // var program: TypedProgram? { state.program }
  // var initTask: Task<TypedProgram, Error>


  public init(lsp: JSONRPCServer, logger: Logger, state: ServerState) {
    self.lsp = lsp
    self.logger = logger
    self.state = state
  }


  public func initialize(_ params: InitializeParams) async -> Result<InitializationResponse, AnyJSONRPCResponseError> {
    return await state.initialize(params)
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

  public func definition(_ params: TextDocumentPositionParams, _ doc: AnalyzedDocument) async -> Result<DefinitionResponse, AnyJSONRPCResponseError> {

    guard let url = ServerState.validateDocumentUrl(params.textDocument.uri) else {
      return .failure(JSONRPCResponseError(code: ErrorCodes.InvalidParams, message: "Invalid document uri: \(params.textDocument.uri)"))
    }

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
    await withAnalyzedDocument(params.textDocument) { doc in
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


  public func documentSymbol(_ params: DocumentSymbolParams, _ doc: AnalyzedDocument) async -> Result<DocumentSymbolResponse, AnyJSONRPCResponseError> {
    let symbols = doc.ast.listDocumentSymbols(doc)
    if symbols.isEmpty {
      return .success(nil)
    }

    // Validate ranges
    let validatedSymbols = symbols.filter(validateRange)

    let result: DocumentSymbolResponse = .optionA(validatedSymbols)

    // Write to result cache
    await state.writeCachedDocumentResult(doc) { (cachedDocument: inout CachedDocumentResult) in
      cachedDocument.symbols = result
    }

    return .success(result)
  }

  func validateRange(_ s: DocumentSymbol) -> Bool {
    if s.selectionRange.start < s.range.start || s.selectionRange.end > s.range.end {
      logger.error("Invalid symbol ranges, selectionRange is outside range: \(s)")
      return false
    }

    return true
  }


  public func documentSymbol(_ params: DocumentSymbolParams) async -> Result<DocumentSymbolResponse, AnyJSONRPCResponseError> {

    await withDocumentContext(params.textDocument) { context in

      // Check if document has been built, otherwise look for cached result
      if let analyzedDocument = await context.pollAnalyzedDocument() {
        return await withAnalyzedDocument(analyzedDocument) { doc in
          await documentSymbol(params, doc)
        }
      }

      // Check if cached results where loaded successfully
      if case let .success(cachedResult) = await context.getCachedDocumentResult() {
        if let cachedSymbols = cachedResult?.symbols {
          logger.debug("Use cached document symbols")
          return .success(cachedSymbols)
        }
      }

      // Otherwise wait for compiler analysis
      return await withAnalyzedDocument(await context.getAnalyzedDocument()) { doc in
        await documentSymbol(params, doc)
      }
    }
  }

  public func diagnostics(_ params: DocumentDiagnosticParams) async -> Result<DocumentDiagnosticReport, AnyJSONRPCResponseError> {


    let docResult = await state.getAnalyzedDocument(params.textDocument)

    switch docResult {
    case .success:
      return .success(RelatedDocumentDiagnosticReport(kind: .full, items: []))
    case let .failure(error):
      switch error {
      case let .diagnostics(d):
      let dList = d.elements.map { LanguageServerProtocol.Diagnostic($0) }
      return .success(RelatedDocumentDiagnosticReport(kind: .full, items: dList))
      case .other:
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


  func withAnalyzedDocument<ResponseT>(_ docResult: Result<AnalyzedDocument, Error>, fn: (AnalyzedDocument) async -> Result<ResponseT?, AnyJSONRPCResponseError>) async -> Result<ResponseT?, AnyJSONRPCResponseError> {

    switch docResult {
    case let .success(doc):
      return await fn(doc)
    case let .failure(error):
      if let d = error as? DiagnosticSet {
        logger.warning("Program build failed\n\n\(d)")
        return .success(nil)
      }
      return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Unknown build error: \(error)"))
    }
  }

  func withAnalyzedDocument<ResponseT>(_ textDocument: TextDocumentIdentifier, fn: (AnalyzedDocument) async -> Result<ResponseT?, AnyJSONRPCResponseError>) async -> Result<ResponseT?, AnyJSONRPCResponseError> {

    let docResult = await state.getAnalyzedDocument(textDocument)

    switch docResult {
    case let .success(doc):
      return await fn(doc)
    case let .failure(error):
      switch error {
      case let .diagnostics(d):
        logger.warning("Program build failed\n\n\(d)")
        return .success(nil)
      case .other:
        return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Unknown build error: \(error)"))
      }
    }
  }

  func withDocumentContext<ResponseT>(_ textDocument: TextDocumentIdentifier, fn: (DocumentContext) async -> Result<ResponseT?, AnyJSONRPCResponseError>) async -> Result<ResponseT?, AnyJSONRPCResponseError> {
    let result = await state.getDocumentContext(textDocument, includeCache: true)

    switch result {
      case let .failure(error):
        return .failure(JSONRPCResponseError(code: ErrorCodes.InvalidParams, message: error.localizedDescription))
      case let .success(context):
        return await fn(context)
    }
  }


  // https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide
  // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens
  public func semanticTokensFull(_ params: SemanticTokensParams) async -> Result<SemanticTokensResponse, AnyJSONRPCResponseError> {
    await withDocumentContext(params.textDocument) { context in

      // Check if document has been built, otherwise look for cached result
      if let analyzedDocument = await context.pollAnalyzedDocument() {
        return await withAnalyzedDocument(analyzedDocument) { doc in
          await semanticTokensFull(params, doc)
        }
      }

      // Check if cached results where loaded successfully
      if case let .success(cachedResult) = await context.getCachedDocumentResult() {
        if let cachedTokens = cachedResult?.semanticTokens {
          logger.debug("Use cached document semantic tokens")
          return .success(cachedTokens)
        }
      }

      // Otherwise wait for compiler analysis
      return await withAnalyzedDocument(await context.getAnalyzedDocument()) { doc in
        await semanticTokensFull(params, doc)
      }
    }
  }

  public func semanticTokensFull(_ params: SemanticTokensParams, _ doc: AnalyzedDocument) async -> Result<SemanticTokensResponse, AnyJSONRPCResponseError> {
    let (ast, program) = (doc.ast, doc.program)
    let tokens = ast.getSematicTokens(params.textDocument.uri, program)
    logger.debug("[\(params.textDocument.uri)] Return \(tokens.count) semantic tokens")

    let result = SemanticTokens(tokens: tokens)

    // Write to result cache
    await state.writeCachedDocumentResult(doc) { (cachedDocument: inout CachedDocumentResult) in
      cachedDocument.semanticTokens = result
    }


    return .success(result)
  }

}


public actor HyloServer {
  let lsp: JSONRPCServer
  // private var ast: AST
  private var state: ServerState
  private let requestHandler: HyloRequestHandler
  private let notificationHandler: HyloNotificationHandler

  public init(_ dataChannel: DataChannel, logger: Logger) {
    lsp = JSONRPCServer(dataChannel)
    self.state = ServerState(lsp: lsp)
    requestHandler = HyloRequestHandler(lsp: lsp, logger: logger, state: state)
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
