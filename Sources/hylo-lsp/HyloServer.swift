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
  public let connection: JSONRPCClientConnection
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
  public let connection: JSONRPCClientConnection
  public let logger: Logger

  var documentProvider: DocumentProvider
  // var ast: AST { documentProvider.ast }
  // var program: TypedProgram? { documentProvider.program }
  // var initTask: Task<TypedProgram, Error>


  public init(connection: JSONRPCClientConnection, logger: Logger, documentProvider: DocumentProvider) {
    self.connection = connection
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

    let resolver = DefinitionResolver(ast: doc.ast, program: doc.program, logger: logger)

    if let response = resolver.resolve(p) {
      return .success(response)
    }

    return .success(nil)
  }

  public func definition(id: JSONId, params: TextDocumentPositionParams) async -> Result<DefinitionResponse, AnyJSONRPCResponseError> {
    await withAnalyzedDocument(params.textDocument) { doc in
      await definition(id: id, params: params, doc: doc)
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
      try await connection.sendNotification(.textDocumentPublishDiagnostics(dp))
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
  let connection: JSONRPCClientConnection
  private let logger: Logger
  private var documentProvider: DocumentProvider
  private let dispatcher: EventDispatcher

  public static let disableLogging = if let disableLogging = ProcessInfo.processInfo.environment["HYLO_LSP_DISABLE_LOGGING"] { !disableLogging.isEmpty } else { false }

  public init(_ dataChannel: DataChannel, logger: Logger) {
    self.logger = logger
    connection = JSONRPCClientConnection(dataChannel)
    self.documentProvider = DocumentProvider(connection: connection, logger: logger)
    let requestHandler = HyloRequestHandler(connection: connection, logger: logger, documentProvider: documentProvider)
    let notificationHandler = HyloNotificationHandler(connection: connection, logger: logger, documentProvider: documentProvider)
    let errorHandler = HyloErrorHandler(logger: logger)

    dispatcher = EventDispatcher(connection: connection, requestHandler: requestHandler, notificationHandler: notificationHandler, errorHandler: errorHandler)
  }

  public func run() async {
    logger.debug("starting server")
    await dispatcher.run()
  }
}
