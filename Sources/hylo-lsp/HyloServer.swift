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
  public let lsp: JSONRPCClientConnection
  public let logger: Logger
  var documentProvider: DocumentProvider
  // var ast: AST { documentProvider.ast }

  public func handleNotification(_ notification: ClientNotification) async {
    let t0 = Date()
    logger.debug("Begin handle notification: \(notification.method)")
    await defaultNotificationDispatch(notification)
    let t = Date().timeIntervalSince(t0)
    logger.debug("Complete handle notification: \(notification.method), after \(Int(t*1000))ms")
  }

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


  public func textDocumentDidOpen(_ params: DidOpenTextDocumentParams) async {
    await documentProvider.registerDocument(params)
  }

  public func textDocumentDidChange(_ params: DidChangeTextDocumentParams) async {
    await documentProvider.updateDocument(params)
  }

  public func textDocumentDidClose(_ params: DidCloseTextDocumentParams) async {
    await documentProvider.unregisterDocument(params)
  }

  public func textDocumentWillSave(_ params: WillSaveTextDocumentParams) async {

  }

  public func textDocumentDidSave(_ params: DidSaveTextDocumentParams) async {
  }

  public func protocolCancelRequest(_ params: CancelParams) async {
    // NOTE: For cancel to work we must pass JSONRPC request ids to handlers
    logger.debug("Cancel request: \(params.id)")
  }

  public func protocolSetTrace(_ params: SetTraceParams) async {

  }

  public func workspaceDidChangeWatchedFiles(_ params: DidChangeWatchedFilesParams) async {

  }

  public func windowWorkDoneProgressCancel(_ params: WorkDoneProgressCancelParams) async {

  }

  public func workspaceDidChangeWorkspaceFolders(_ params: DidChangeWorkspaceFoldersParams) async {
    await documentProvider.workspaceDidChangeWorkspaceFolders(params)
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
  public let lsp: JSONRPCClientConnection
  public let logger: Logger

  var documentProvider: DocumentProvider
  // var ast: AST { documentProvider.ast }
  // var program: TypedProgram? { documentProvider.program }
  // var initTask: Task<TypedProgram, Error>


  public init(lsp: JSONRPCClientConnection, logger: Logger, documentProvider: DocumentProvider) {
    self.lsp = lsp
    self.logger = logger
    self.documentProvider = documentProvider
  }

  public func handleRequest(id: JSONId, request: ClientRequest) async {
    let t0 = Date()
    logger.debug("Begin handle request: \(request.method)")
    await defaultRequestDispatch(id: id, request: request)
    let t = Date().timeIntervalSince(t0)
    logger.debug("Complete handle request: \(request.method), after \(Int(t*1000))ms")
  }


  public func initialize(id: JSONId, params: InitializeParams) async -> Result<InitializationResponse, AnyJSONRPCResponseError> {
    return await documentProvider.initialize(params)
  }

  public func shutdown(id: JSONId) async {

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

  public func definition(id: JSONId, params: TextDocumentPositionParams, doc: AnalyzedDocument) async -> Result<DefinitionResponse, AnyJSONRPCResponseError> {

    guard let url = DocumentProvider.validateDocumentUrl(params.textDocument.uri) else {
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

  public func definition(id: JSONId, params: TextDocumentPositionParams) async -> Result<DefinitionResponse, AnyJSONRPCResponseError> {
    await withAnalyzedDocument(params.textDocument) { doc in
      await definition(id: id, params: params, doc: doc)
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


  public func documentSymbol(id: JSONId, params: DocumentSymbolParams, ast: AST) async -> Result<DocumentSymbolResponse, AnyJSONRPCResponseError> {
    let symbols = ast.listDocumentSymbols(params.textDocument.uri, logger: logger)
    if symbols.isEmpty {
      return .success(nil)
    }

    // Validate ranges
    let validatedSymbols = symbols.filter(validateRange)
    return .success(.optionA(validatedSymbols))
  }

  func validateRange(_ s: DocumentSymbol) -> Bool {
    if s.selectionRange.start < s.range.start || s.selectionRange.end > s.range.end {
      logger.error("Invalid symbol ranges, selectionRange is outside range: \(s)")
      return false
    }

    return true
  }


  public func documentSymbol(id: JSONId, params: DocumentSymbolParams) async -> Result<DocumentSymbolResponse, AnyJSONRPCResponseError> {

    await withDocumentAST(params.textDocument) { ast in
      await documentSymbol(id: id, params: params, ast: ast)
    }
  }

  public func diagnostics(id: JSONId, params: DocumentDiagnosticParams) async -> Result<DocumentDiagnosticReport, AnyJSONRPCResponseError> {

    let docResult = await documentProvider.getAnalyzedDocument(params.textDocument)

    switch docResult {
    case .success:
      return .success(RelatedDocumentDiagnosticReport(kind: .full, items: []))
    case let .failure(error):
      switch error {
      case let .diagnostics(d):
      return .success(buildDiagnosticReport(uri: params.textDocument.uri, diagnostics: d))
      case .other:
        return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Unknown build error: \(error)"))
      }
    }
  }

  func buildDiagnosticReport(uri: DocumentUri, diagnostics: DiagnosticSet) -> RelatedDocumentDiagnosticReport {
    let matching = diagnostics.elements.filter { $0.site.file.url.absoluteString == uri }
    let nonMatching = diagnostics.elements.filter { $0.site.file.url.absoluteString != uri }

    let items = matching.map { LanguageServerProtocol.Diagnostic($0) }
    let related = nonMatching.reduce(into: [String: LanguageServerProtocol.DocumentDiagnosticReport]()) {
      let d = LanguageServerProtocol.Diagnostic($1)
      $0[$1.site.file.url.absoluteString] = DocumentDiagnosticReport(kind: .full, items: [d])
    }

    return RelatedDocumentDiagnosticReport(kind: .full, items: items, relatedDocuments: related)
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


  func withDocument<DocT, ResponseT>(_ docResult: Result<DocT, Error>, fn: (DocT) async -> Result<ResponseT?, AnyJSONRPCResponseError>) async -> Result<ResponseT?, AnyJSONRPCResponseError> {

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

    let docResult = await documentProvider.getAnalyzedDocument(textDocument)

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

  func withDocumentAST<ResponseT>(_ textDocument: TextDocumentIdentifier, fn: (AST) async -> Result<ResponseT?, AnyJSONRPCResponseError>) async -> Result<ResponseT?, AnyJSONRPCResponseError> {
    let result = await documentProvider.getAST(textDocument)

    switch result {
      case let .failure(error):
        let errorMsg = switch error {
        case .diagnostics: "Failed to build AST"
        case let .other(e): e.localizedDescription
        }
        return .failure(JSONRPCResponseError(code: ErrorCodes.InvalidParams, message: errorMsg))
      case let .success(ast):
        return await fn(ast)
    }
  }


  // https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide
  // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens
  public func semanticTokensFull(id: JSONId, params: SemanticTokensParams) async -> Result<SemanticTokensResponse, AnyJSONRPCResponseError> {

    await withDocumentAST(params.textDocument) { ast in
      await semanticTokensFull(id: id, params: params, ast: ast)
    }
  }

  public func semanticTokensFull(id: JSONId, params: SemanticTokensParams, ast: AST) async -> Result<SemanticTokensResponse, AnyJSONRPCResponseError> {
    let tokens = ast.getSematicTokens(params.textDocument.uri, logger: logger)
    logger.debug("[\(params.textDocument.uri)] Return \(tokens.count) semantic tokens")
    return .success(SemanticTokens(tokens: tokens))
  }
}

public struct HyloErrorHandler : ErrorHandler {
  let logger: Logger

	public func internalError(_ error: Error) async {
    logger.debug("LSP stream error: \(error)")
  }
}

public actor HyloServer {
  let lsp: JSONRPCClientConnection
  private let logger: Logger
  private var documentProvider: DocumentProvider
  private let dispatcher: EventDispatcher

  public static let disableLogging = if let disableLogging = ProcessInfo.processInfo.environment["HYLO_LSP_DISABLE_LOGGING"] { !disableLogging.isEmpty } else { false }

  public init(_ dataChannel: DataChannel, logger: Logger) {
    self.logger = logger
    lsp = JSONRPCClientConnection(dataChannel)
    self.documentProvider = DocumentProvider(lsp: lsp, logger: logger)
    let requestHandler = HyloRequestHandler(lsp: lsp, logger: logger, documentProvider: documentProvider)
    let notificationHandler = HyloNotificationHandler(lsp: lsp, logger: logger, documentProvider: documentProvider)
    let errorHandler = HyloErrorHandler(logger: logger)

    dispatcher = EventDispatcher(connection: lsp, requestHandler: requestHandler, notificationHandler: notificationHandler, errorHandler: errorHandler)
  }

  public func run() async {
    logger.debug("starting server")
    await dispatcher.run()
  }
}
