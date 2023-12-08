import JSONRPC
import Foundation
import LanguageServerProtocol
import LanguageServer
import StandardLibrary
@preconcurrency import Core
import FrontEnd
import Logging

public protocol TextDocumentProtocol {
  var uri: DocumentUri { get }
}

extension TextDocumentIdentifier : TextDocumentProtocol {}
extension TextDocumentItem : TextDocumentProtocol {}
extension VersionedTextDocumentIdentifier : TextDocumentProtocol {}

public enum GetDocumentContextError : Error {
  case invalidUri(DocumentUri)
  case documentNotOpened(DocumentUri)
}

public actor DocumentProvider {
  private var documents: [DocumentUri:DocumentContext]
  public let logger: Logger
  let connection: JSONRPCClientConnection
  var rootUri: String?
  var workspaceFolders: [WorkspaceFolder]
  var stdlibCache: [URL:AST]

  public let defaultStdlibFilepath: URL

  public init(connection: JSONRPCClientConnection, logger: Logger) {
    self.logger = logger
    documents = [:]
    stdlibCache = [:]
    self.connection = connection
    self.workspaceFolders = []
    defaultStdlibFilepath = DocumentProvider.loadDefaultStdlibFilepath(logger: logger)
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

    if let workspaceFolders = params.workspaceFolders {
      self.workspaceFolders = workspaceFolders
    }

    // From spec: If both `rootPath` and `rootUri` are set `rootUri` wins.
    if let rootUri = params.rootUri {
      self.rootUri = rootUri
    }
    else if let rootPath = params.rootPath {
      self.rootUri = rootPath
    }

    logger.info("Initialize in working directory: \(FileManager.default.currentDirectoryPath), with rootUri: \(rootUri ?? "nil"), workspace folders: \(workspaceFolders)")

    // if let rootUri = params.rootUri {
    //   // guard let path = URL(string: rootUri) else {
    //   //   return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "invalid rootUri uri format"))
    //   // }

    //   // let filepath = path.absoluteURL.path() // URL path to filesystem path
    //   // logger.debug("filepath: \(filepath)")

    //   // guard let items = try? fm.contentsOfDirectory(atPath: filepath) else {
    //   //   return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "could not list rootUri directory: \(path)"))
    //   // }

    //   // do {
    //   //   state.program = try state._buildProgram(items.map { path.appending(path: $0) })
    //   // }
    //   // catch {
    //   //   return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "could not build rootUri directory: \(path), error: \(error)"))
    //   // }

    //   return .success(InitializationResponse(capabilities: getServerCapabilities(), serverInfo: serverInfo))
    // }
    // else {
    //   // return .failure(JSONRPCResponseError(code: ErrorCodes.ServerNotInitialized, message: "expected rootUri parameter"))

    //   logger.debug("init without rootUri")
    // }
    let serverInfo = ServerInfo(name: "hylo", version: "0.1.0")
    return .success(InitializationResponse(capabilities: getServerCapabilities(), serverInfo: serverInfo))
  }

  public func workspaceDidChangeWorkspaceFolders(_ params: DidChangeWorkspaceFoldersParams) async {
    let removed = params.event.removed
    let added = params.event.added
    workspaceFolders = workspaceFolders.filter { removed.contains($0) }
    workspaceFolders.append(contentsOf: added)
  }

  private static func loadDefaultStdlibFilepath(logger: Logger) -> URL {
    if let path = ProcessInfo.processInfo.environment["HYLO_STDLIB_PATH"] {
      logger.info("Hylo stdlib filepath from HYLO_STDLIB_PATH: \(path)")
      return URL(fileURLWithPath: path)
    }
    else {
      return StandardLibrary.freestandingLibrarySourceRoot
    }
  }

  public func isStdlibDocument(_ uri: DocumentUri) -> Bool {
    let (_, isStdlibDocument) = getStdlibPath(uri)
    return isStdlibDocument
  }

  public func getStdlibPath(_ uri: DocumentUri) -> (stdlibPath: URL, isStdlibDocument: Bool) {
    guard let url = URL(string: uri) else {
      logger.error("invalid document uri: \(uri)")
      return (defaultStdlibFilepath, false)
    }

    var it = url.deletingLastPathComponent()

    // Check if current document is inside a stdlib source directory
    while it.path != "/" {
      let voidPath = NSString.path(withComponents: [it.path, "Core", "Void.hylo"])
      let fm = FileManager.default
      var isDirectory: ObjCBool = false
      if fm.fileExists(atPath: voidPath, isDirectory: &isDirectory) && !isDirectory.boolValue {
        logger.info("Use local stdlib path: \(it.path)")
        return (it, true)
      }

      it = it.deletingLastPathComponent()
    }

    return (defaultStdlibFilepath, false)
  }

  func getRelativePathInWorkspace(_ uri: DocumentUri, relativeTo workspace: DocumentUri) -> String? {
    if uri.starts(with: workspace) {
      let start = uri.index(uri.startIndex, offsetBy: workspace.count)
      let tail = uri[start...]
      let relPath = tail.trimmingPrefix("/")
      return String(relPath)
    }
    else {
      return nil
    }
  }

  struct WorkspaceFile {
    let workspace: DocumentUri
    let relativePath: String
  }


  func getWorkspaceFile(_ uri: DocumentUri) -> WorkspaceFile? {
    var wsRoots = workspaceFolders.map { $0.uri }
    if let rootUri = rootUri {
      wsRoots.append(rootUri)
    }

    var closest: WorkspaceFile?

    // Look for the closest matching workspace root
    for root in wsRoots {
      if let relPath = getRelativePathInWorkspace(uri, relativeTo: root) {
        if closest == nil || relPath.count < closest!.relativePath.count {
          closest = WorkspaceFile(workspace: root, relativePath: relPath)
        }
      }
    }

    return closest
  }

  func uriAsFilepath(_ uri: DocumentUri) -> String? {
    guard let url = URL.init(string: uri) else {
      return nil
    }

    return url.path
  }

  private func buildStdlibAST(_ stdlibPath: URL) throws -> AST {
    let sourceFiles = try sourceFiles(in: [stdlibPath]).map { file in

      // We need to replace stdlib files from in memory buffers if they have unsaved changes
      if let context = documents[file.url.absoluteString] {
        logger.debug("Replace content for stdlib source file: \(file.url)")
        return SourceFile(contents: context.doc.text, fileID: file.url)
      }
      else {
        return file
      }
    }

    return try AST(sourceFiles: sourceFiles)
  }

  // We cache stdlib AST, and since AST is struct the cache values are implicitly immutable (thanks MVS!)
  private func getStdlibAST(_ stdlibPath: URL) throws -> AST {
    if let ast = stdlibCache[stdlibPath] {
      return ast
    }
    else {
      let ast = try buildStdlibAST(stdlibPath)
      stdlibCache[stdlibPath] = ast
      return ast
    }
  }

  private func buildAST(uri: DocumentUri, stdlibPath: URL, sourceFiles: [SourceFile]) throws -> AST {
    var diagnostics = DiagnosticSet()
    logger.debug("Build ast for document: \(uri), with stdlibPath: \(stdlibPath)")

    var ast = try getStdlibAST(stdlibPath)

    if !sourceFiles.isEmpty {
        let productName = "lsp-build"
        // let sourceFiles = try sourceFiles(in: inputs)
      _ = try ast.makeModule(productName, sourceCode: sourceFiles, builtinModuleAccess: false, diagnostics: &diagnostics)
    }

    return ast
  }

  private func buildProgram(uri: DocumentUri, ast: AST) throws -> AnalyzedDocument {
    // let inputs = files.map { URL.init(fileURLWithPath: $0)}
    let compileSequentially = false

    var diagnostics = DiagnosticSet()

    let t0 = Date()
    let p = try TypedProgram(
    annotating: ScopedProgram(ast), inParallel: !compileSequentially,
    reportingDiagnosticsTo: &diagnostics,
    tracingInferenceIf: nil)

    let typeCheckTime = Date().timeIntervalSince(t0)
    logger.debug("Program is built: \(uri)")

    let profiling = DocumentProfiling(stdlibParsing: TimeInterval(), ASTParsing: TimeInterval(), typeChecking: typeCheckTime)

    return AnalyzedDocument(uri: uri, ast: ast, program: p, profiling: profiling)
  }

  // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#uri
  // > Over the wire, it will still be transferred as a string, but this guarantees that the contents of that string can be parsed as a valid URI.
  public static func validateDocumentUri(_ uri: DocumentUri) -> DocumentUri? {
    if let url = URL(string: uri) {

      // Make sure the URL is a fully qualified path with scheme
      if url.scheme != nil {
        return uri
      }
    }

    return nil
  }

  public static func validateDocumentUrl(_ uri: DocumentUri) -> URL? {
    if let url = URL(string: uri) {

      // Make sure the URL is a fully qualified path with scheme
      if url.scheme != nil {
        return url
      }
    }

    return nil
  }

  public func updateDocument(_ params: DidChangeTextDocumentParams) {
    let uri = params.textDocument.uri
    guard let context = documents[uri] else {
      logger.error("Could not find opened document: \(uri)")
      return
    }

    do {
      let updatedDoc = try context.doc.withAppliedChanges(params.contentChanges, nextVersion: params.textDocument.version)
      context.doc = updatedDoc
      context.astTask = nil
      context.buildTask = nil
      logger.debug("Updated changed document: \(uri), version: \(updatedDoc.version ?? -1)")

      // NOTE: We also need to invalidate cached stdlib AST if the edited document is part of the stdlib
      let (stdlibPath, isStdlibDocument) = getStdlibPath(uri)
      if isStdlibDocument {
        stdlibCache[stdlibPath] = nil
      }
    }
    catch {
      logger.error("Failed to apply document changes")
    }
  }

  public func registerDocument(_ params: DidOpenTextDocumentParams) {
    let doc = Document(textDocument: params.textDocument)
    let context = DocumentContext(doc)
    // requestDocument(doc)
    logger.debug("Register opened document: \(doc.uri)")
    documents[doc.uri] = context
  }

  public func unregisterDocument(_ params: DidCloseTextDocumentParams) {
    let uri = params.textDocument.uri
    documents[uri] = nil
  }


  func implicitlyRegisterDocument(_ uri: DocumentUri)-> DocumentContext? {
    guard let url = URL.init(string: uri) else {
      return nil
    }

    guard let text = try? String(contentsOf: url) else {
      return nil
    }

    let doc = Document(uri: uri, version: 0, text: text)
    return DocumentContext(doc)
  }


  func getDocumentContext(_ textDocument: TextDocumentProtocol) -> Result<DocumentContext, GetDocumentContextError> {
    getDocumentContext(textDocument.uri)
  }

  func getDocumentContext(_ uri: DocumentUri) -> Result<DocumentContext, GetDocumentContextError> {
    guard let uri = DocumentProvider.validateDocumentUri(uri) else {
      return .failure(.invalidUri(uri))
    }

    guard let context = documents[uri] else {
      // NOTE: We can not assume document is opened, VSCode apparently does not guarantee ordering
      // Specifically `textDocument/diagnostic` -> `textDocument/didOpen` has been observed

      // return .failure(.documentNotOpened(uri))

      logger.warning("Implicitly registering unopened document: \(uri)")
      if let context = implicitlyRegisterDocument(uri) {
        return .success(context)
      }
      else {
        return .failure(.invalidUri(uri))
      }
    }

    return .success(context)
  }

  public func getAST(_ textDocument: TextDocumentProtocol) async -> Result<AST, DocumentError> {
    switch getDocumentContext(textDocument) {
      case let .failure(error):
        return .failure(.other(error))
      case let .success(context):
        return await getAST(context)
    }
  }

  public func getAnalyzedDocument(_ textDocument: TextDocumentProtocol) async -> Result<AnalyzedDocument, DocumentError> {
    switch getDocumentContext(textDocument) {
      case let .failure(error):
        return .failure(.other(error))
      case let .success(context):
        return await getAnalyzedDocument(context)
    }
  }

  private func createASTTask(_ context: DocumentContext) -> Task<AST, Error> {
    if context.astTask == nil {
      let uri = context.uri
      let (stdlibPath, isStdlibDocument) = getStdlibPath(uri)

      let sourceFiles: [SourceFile]

      if isStdlibDocument {
        sourceFiles = []
      }
      else {
        let url = URL.init(string: uri)!
        sourceFiles = [SourceFile(contents: context.doc.text, fileID: url)]
      }

      context.astTask = Task {
        return try buildAST(uri: uri, stdlibPath: stdlibPath, sourceFiles: sourceFiles)
      }
    }

    return context.astTask!
  }

  private func getAST(_ context: DocumentContext) async -> Result<AST, DocumentError> {
    do {
      let astTask = createASTTask(context)
      let ast = try await astTask.value
      return .success(ast)
    }
    catch let d as DiagnosticSet {
      // NOTE: We want to be able to use partial AST, need to update Hylo call to not throw
      return .failure(.diagnostics(d))
    }
    catch {
      return .failure(.other(error))
    }
  }

  private func getAnalyzedDocument(_ context: DocumentContext) async -> Result<AnalyzedDocument, DocumentError> {
    if context.buildTask == nil {
      context.buildTask = Task {
        let astTask = createASTTask(context)
        let ast = try await astTask.value
        return try buildProgram(uri: context.uri, ast: ast)
      }
    }

    do {
      let doc = try await context.buildTask!.value
      return .success(doc)
    }
    catch let d as DiagnosticSet {
      return .failure(.diagnostics(d))
    }
    catch {
      return .failure(.other(error))
    }
  }


#if false
  // NOTE: We currently write cached results inside the workspace
  // These should perhaps be stored outside workspace, but then it is more important
  // to implement some kind of garbage collection for out-dated workspace cache entries
  private func getResultCacheFilepath(_ wsFile: WorkspaceFile) -> String {
    NSString.path(withComponents: [uriAsFilepath(wsFile.workspace)!, ".hylo-lsp", "cache", wsFile.relativePath + ".json"])
  }

  private func loadCachedDocumentResult(_ uri: DocumentUri) -> CachedDocumentResult? {
    do {
      guard let filepath = uriAsFilepath(uri) else {
        return nil
      }

      guard let wsFile = getWorkspaceFile(uri) else {
        logger.debug("Cached LSP result did not locate relative workspace path: \(uri)")
        return nil
      }

      let fm = FileManager.default

      let attr = try fm.attributesOfItem(atPath: filepath)
      guard let modificationDate = attr[FileAttributeKey.modificationDate] as? Date else {
        return nil
      }

      let cachedDocumentResultPath = getResultCacheFilepath(wsFile)
      let url = URL(fileURLWithPath: cachedDocumentResultPath)

      guard fm.fileExists(atPath: cachedDocumentResultPath) else {
        logger.debug("Cached LSP result does not exist: \(cachedDocumentResultPath)")
        return nil
      }

      let cachedDocumentAttr = try fm.attributesOfItem(atPath: cachedDocumentResultPath)
      guard let cachedDocumentModificationDate = cachedDocumentAttr[FileAttributeKey.modificationDate] as? Date else {
        return nil
      }

      guard cachedDocumentModificationDate > modificationDate else {
        logger.debug("Cached LSP result is out-of-date: \(cachedDocumentResultPath), source code date: \(modificationDate), cache file date: \(cachedDocumentModificationDate)")
        return nil
      }

      logger.debug("Found cached LSP result file: \(cachedDocumentResultPath)")
      let jsonData = try Data(contentsOf: url)
      return try JSONDecoder().decode(CachedDocumentResult.self, from: jsonData)
    }
    catch {
      logger.error("Failed to read cached result: \(error)")
      return nil
    }
  }

  public func writeCachedDocumentResult(_ doc: AnalyzedDocument, writer: (inout CachedDocumentResult) -> Void) async {
    guard let wsFile = getWorkspaceFile(doc.uri) else {
      logger.warning("Cached LSP result did not locate relative workspace path: \(doc.uri)")
      return
    }

    let t0 = Date()

    let cachedDocumentResultPath = getResultCacheFilepath(wsFile)
    let url = URL(fileURLWithPath: cachedDocumentResultPath)
    let fm = FileManager.default
    // var cachedDocument = CachedDocumentResult(uri: doc.uri)
    var cachedDocument = if let doc = loadCachedDocumentResult(doc.uri) { doc } else { CachedDocumentResult(uri: doc.uri) }

    do {

      writer(&cachedDocument)
      let encoder = JSONEncoder()
      encoder.outputFormatting = .prettyPrinted
      let jsonData = try encoder.encode(cachedDocument)
      let dirUrl = url.deletingLastPathComponent()

      if !fm.fileExists(atPath: dirUrl.path) {
        try fm.createDirectory(
          at: dirUrl,
          withIntermediateDirectories: true,
          attributes: nil
        )
      }

      try jsonData.write(to: url)
      let t = Date().timeIntervalSince(t0)
      logger.debug("Wrote result cache: \(cachedDocumentResultPath), cache operation took \(t.milliseconds)ms")
    }
    catch {
      logger.error("Failed to write cached result: \(error)")
    }

  }
#endif
}

