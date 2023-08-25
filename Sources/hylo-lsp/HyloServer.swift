import JSONRPC
import LanguageServerProtocol
import Foundation

import Core
import FrontEnd
import IR
import HyloModule

public class LspState {
  var ast: AST
  let lsp: LspServer
  var program: TypedProgram?

  public init(ast: AST, lsp: LspServer) {
    self.ast = ast
    self.lsp = lsp
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


public struct ValNotificationHandler : NotificationHandler {
  var state: LspState
  var ast: AST { state.ast }
  static let productName = "lsp-build"


  private func withErrorLogging(_ fn: () throws -> Void) {
    do {
      try fn()
    }
    catch {
      print("Error: \(error)")
    }
  }

  private func withErrorLogging(_ fn: () async throws -> Void) async {
    do {
      try await fn()
    }
    catch {
      print("Error: \(error)")
    }

  }

  public func initialized(_ params: InitializedParams) async {

  }

  public func exit() async {

  }

  public func textDocumentDidOpen(_ params: DidOpenTextDocumentParams) async {
    let uri = params.textDocument.uri
    print("textDocumentDidOpen: \(uri)")
    // print("lib uri: \(HyloModule.standardLibrary!.absoluteString)")
    // if uri.commonPrefix(with: HyloModule.standardLibrary!.absoluteString) == HyloModule.standardLibrary!.absoluteString {
    if uri.contains("hyloc/Library/Hylo") {
      // print("document is lib")
    }
    else {
      // print("document is not lib")
      // let inputs = [URL.init(string: uri)!]
      // let importBuiltinModule = false
      // let compileSequentially = false

      // var diagnostics = DiagnosticSet()

      // withErrorLogging {
      //   _ = try state.ast.makeModule(ValNotificationHandler.productName, sourceCode: sourceFiles(in: inputs),
      //   builtinModuleAccess: importBuiltinModule, diagnostics: &diagnostics)

      //   state.program = try TypedProgram(
      //   annotating: ScopedProgram(state.ast), inParallel: !compileSequentially,
      //   reportingDiagnosticsTo: &diagnostics,
      //   tracingInferenceIf: nil)
      // }
    }
  }

  public func textDocumentDidChange(_ params: DidChangeTextDocumentParams) async {

  }

  public func textDocumentDidClose(_ params: DidCloseTextDocumentParams) async {

  }

  public func textDocumentWillSave(_ params: WillSaveTextDocumentParams) async {

  }

  public func textDocumentDidSave(_ params: DidSaveTextDocumentParams) async {

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

public struct ValRequestHandler : RequestHandler {
  var state: LspState
  var ast: AST { state.ast }
  var program: TypedProgram? { state.program }
  // var initTask: Task<TypedProgram, Error>

  private let serverInfo: ServerInfo

  public init(serverInfo: ServerInfo, state: LspState) {
    self.serverInfo = serverInfo
    self.state = state
  }

  private func getServerCapabilities() -> ServerCapabilities {
    var s = ServerCapabilities()
    s.textDocumentSync = .optionA(TextDocumentSyncOptions(openClose: false, change: TextDocumentSyncKind.full, willSave: false, willSaveWaitUntil: false, save: nil))
    s.textDocumentSync = .optionB(TextDocumentSyncKind.full)
    s.definitionProvider = .optionA(true)
    s.typeDefinitionProvider = .optionA(true)
    s.documentSymbolProvider = .optionA(true)

    return s
  }

  private func buildProgram(_ inputs: [URL]) async throws {
    // let inputs = files.map { URL.init(fileURLWithPath: $0)}
    let importBuiltinModule = false
    let compileSequentially = false

    var diagnostics = DiagnosticSet()
    print("buildProgram: \(inputs)")

    _ = try state.ast.makeModule(ValNotificationHandler.productName, sourceCode: sourceFiles(in: inputs),
    builtinModuleAccess: importBuiltinModule, diagnostics: &diagnostics)

    state.program = try TypedProgram(
    annotating: ScopedProgram(state.ast), inParallel: !compileSequentially,
    reportingDiagnosticsTo: &diagnostics,
    tracingInferenceIf: nil)
    print("program is built")
  }



  public func initialize(_ params: InitializeParams) async -> Result<InitializationResponse, AnyJSONRPCResponseError> {
    // do {
    //   try await state.lsp.sendNotification(.windowShowMessage(ShowMessageParams(type: .warning, message: "foo")))
    //   try await state.lsp.sendNotification(.windowLogMessage(LogMessageParams(type: .warning, message: "foo")))
    // }
    // catch {
    //   print("error: \(error)")
    // }

    // print("sent log")
    // fflush(stdout)


    let fm = FileManager.default

    if let rootUri = params.rootUri {
      guard let path = URL(string: rootUri) else {
        return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "invalid rootUri uri format"))
      }

      let filepath = path.absoluteURL.path() // URL path to filesystem path
      print("filepath: \(filepath)")
      fflush(stdout)

      guard let items = try? fm.contentsOfDirectory(atPath: filepath) else {
        return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "could not list rootUri directory: \(path)"))
      }

      do {
        try await buildProgram(items.map { path.appending(path: $0) })
      }
      catch {
        return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "could not build rootUri directory: \(path), error: \(error)"))
      }

      return .success(InitializationResponse(capabilities: getServerCapabilities(), serverInfo: serverInfo))
    }
    else {
      // return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "expected rootUri parameter"))
      return .success(InitializationResponse(capabilities: getServerCapabilities(), serverInfo: serverInfo))
    }
  }

  public func shutdown() async {

  }

  public func workspaceExecuteCommand(_ params: ExecuteCommandParams) async -> Result<LSPAny?, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func workspaceWillCreateFiles(_ params: CreateFilesParams) async -> Result<WorkspaceEdit?, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func workspaceWillRenameFiles(_ params: RenameFilesParams) async -> Result<WorkspaceEdit?, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func workspaceWillDeleteFiles(_ params: DeleteFilesParams) async -> Result<WorkspaceEdit?, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func workspaceSymbol(_ params: WorkspaceSymbolParams) async -> Result<WorkspaceSymbolResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func workspaceSymbolResolve(_ params: WorkspaceSymbol) async -> Result<WorkspaceSymbol, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func textDocumentWillSaveWaitUntil(_ params: WillSaveTextDocumentParams) async -> Result<[TextEdit]?, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func completion(_ params: CompletionParams) async -> Result<CompletionResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func completionItemResolve(_ params: CompletionItem) async -> Result<CompletionItem, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func hover(_ params: TextDocumentPositionParams) async -> Result<HoverResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func signatureHelp(_ params: TextDocumentPositionParams) async -> Result<SignatureHelpResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func declaration(_ params: TextDocumentPositionParams) async -> Result<DeclarationResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func definition(_ params: TextDocumentPositionParams) async -> Result<DefinitionResponse, AnyJSONRPCResponseError> {
    guard let program = program else {
      return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Compilation missing"))
    }

    let url = URL.init(string: params.textDocument.uri)!
    guard let f = try? SourceFile(contentsOf: url) else {
      return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Invalid document uri"))
    }

    let pos = params.position

    let p = SourcePosition(line: pos.line+1, column: pos.character+1, in: f)
    print("p: \(p)")

    if let id = ast.findNode(p) {
      print("found: \(id), in num nodes: \(ast.numNodes)")
      // let s = program.nodeToScope[id]
      let node = ast[id]
      print("Found node: \(node), id: \(id)")

      if let n = NameExpr.ID(id) {
        // let d = program[n].referredDecl
        let d = program.referredDecl[n]

        // print("d: \(d)")
        if case let .direct(d, args) = d {
          print("d: \(d), generic args: \(args), name: \(program.name(of: d)!)")
          // let fnNode = ast[d]
          // let range = LSPRange(hylocRange: fnNode.site)
          let range = nameRange(of: d)
          let response = Location(uri: url.absoluteString, range: LSPRange(range!))
          return .success(.optionA(response))
          // if let fid = FunctionDecl.ID(d) {
          //   let f = sourceModule.functions[Function.ID(fid)]!
          //   print("Function: \(f)")
          // }
        }
      }
    }

    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
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
    default:
      return nil
    }
  }


  public func typeDefinition(_ params: TextDocumentPositionParams) async -> Result<TypeDefinitionResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func implementation(_ params: TextDocumentPositionParams) async -> Result<ImplementationResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func diagnostics(_ params: DocumentDiagnosticParams) async -> Result<DocumentDiagnosticReport, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func documentHighlight(_ params: DocumentHighlightParams) async -> Result<DocumentHighlightResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func documentSymbol(_ params: DocumentSymbolParams) async -> Result<DocumentSymbolResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func codeAction(_ params: CodeActionParams) async -> Result<CodeActionResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func codeActionResolve(_ params: CodeAction) async -> Result<CodeAction, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func codeLens(_ params: CodeLensParams) async -> Result<CodeLensResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func codeLensResolve(_ params: CodeLens) async -> Result<CodeLens, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func selectionRange(_ params: SelectionRangeParams) async -> Result<SelectionRangeResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func linkedEditingRange(_ params: LinkedEditingRangeParams) async -> Result<LinkedEditingRangeResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func prepareCallHierarchy(_ params: CallHierarchyPrepareParams) async -> Result<CallHierarchyPrepareResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func prepareRename(_ params: PrepareRenameParams) async -> Result<PrepareRenameResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func rename(_ params: RenameParams) async -> Result<RenameResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func documentLink(_ params: DocumentLinkParams) async -> Result<DocumentLinkResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func documentLinkResolve(_ params: DocumentLink) async -> Result<DocumentLink, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func documentColor(_ params: DocumentColorParams) async -> Result<DocumentColorResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func colorPresentation(_ params: ColorPresentationParams) async -> Result<ColorPresentationResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func formatting(_ params: DocumentFormattingParams) async -> Result<FormattingResult, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func rangeFormatting(_ params: DocumentRangeFormattingParams) async -> Result<FormattingResult, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func onTypeFormatting(_ params: DocumentOnTypeFormattingParams) async -> Result<FormattingResult, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func references(_ params: ReferenceParams) async -> Result<ReferenceResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func foldingRange(_ params: FoldingRangeParams) async -> Result<FoldingRangeResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func moniker(_ params: MonkierParams) async -> Result<MonikerResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func semanticTokensFull(_ params: SemanticTokensParams) async -> Result<SemanticTokensResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func semanticTokensFullDelta(_ params: SemanticTokensDeltaParams) async -> Result<SemanticTokensDeltaResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func semanticTokensRange(_ params: SemanticTokensRangeParams) async -> Result<SemanticTokensResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func callHierarchyIncomingCalls(_ params: CallHierarchyIncomingCallsParams) async -> Result<CallHierarchyIncomingCallsResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func callHierarchyOutgoingCalls(_ params: CallHierarchyOutgoingCallsParams) async -> Result<CallHierarchyOutgoingCallsResponse, AnyJSONRPCResponseError> {
    return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO"))
  }

  public func custom(_ method: String, _ params: LSPAny) async -> Result<LSPAny, AnyJSONRPCResponseError>{
    print("custom method: \(method), params: \(params)")
    return .success(params)
  }
}


public actor HyloServer {
   let lsp: LspServer
  // private var ast: AST
  private var state: LspState
  private let requestHandler: ValRequestHandler
  private let notificationHandler: ValNotificationHandler

  public init(_ dataChannel: DataChannel, useStandardLibrary: Bool = true) {
    lsp = LspServer(dataChannel)
    let serverInfo = ServerInfo(name: "val", version: "0.1")
    let ast = useStandardLibrary ? AST.standardLibrary : AST.coreModule
    self.state = LspState(ast: ast, lsp: lsp)
    requestHandler = ValRequestHandler(serverInfo: serverInfo, state: state)
    notificationHandler = ValNotificationHandler(state: state)

    // Task {
		// 	await monitorRequests()
		// }

    // Task {
		// 	await monitorNotifications()
		// }
  }

  public func run() async {
    async let t1: () = monitorRequests()
    async let t2: () = monitorNotifications()

    // do {
    //   // try await lsp.sendNotification(.windowShowMessage(ShowMessageParams(type: .warning, message: "foo")))
    //   try await lsp.sendNotification(.windowLogMessage(LogMessageParams(type: .warning, message: "foo")))
    // }
    // catch {
    //   print("error: \(error)")
    // }

    _ = await [t1, t2]
  }

  public func monitorRequests() async {
    for await request in lsp.requestSequence {
      await requestHandler.handleRequest(request)
    }
  }

  public func monitorNotifications() async {
    for await notification in lsp.notificationSequence {
      await notificationHandler.handleNotification(notification)
    }
  }
}
