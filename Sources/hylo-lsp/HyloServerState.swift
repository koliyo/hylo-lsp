import JSONRPC
import Foundation
import LanguageServerProtocol
import LanguageServerProtocol_Server
import HyloModule
import Core
import FrontEnd
import Logging

public protocol TextDocumentProtocol {
  var uri: DocumentUri { get }
}

extension TextDocumentIdentifier : TextDocumentProtocol {}
extension TextDocumentItem : TextDocumentProtocol {}
extension VersionedTextDocumentIdentifier : TextDocumentProtocol {}

public actor ServerState {
  private var documents: [DocumentUri:DocumentContext]
  // public let logger: Logger
  let lsp: JSONRPCServer
  var rootUri: String?
  var workspaceFolders: [WorkspaceFolder]

  public static let defaultStdlibFilepath: URL = loadDefaultStdlibFilepath()
  public static let useCaching = if let useCaching = ProcessInfo.processInfo.environment["HYLO_LSP_CACHING"] { !useCaching.isEmpty } else { false }
  public static let disableLogging = if let disableLogging = ProcessInfo.processInfo.environment["HYLO_LSP_DISABLE_LOGGING"] { !disableLogging.isEmpty } else { false }

  public init(lsp: JSONRPCServer) {
    // self.logger = logger
    documents = [:]
    self.lsp = lsp
    self.workspaceFolders = []
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

  // private static func loadStdlibProgram() throws -> TypedProgram {
  //   let ast = try AST(libraryRoot: defaultStdlibFilepath)

  //   var diagnostics = DiagnosticSet()
  //   return try TypedProgram(
  //   annotating: ScopedProgram(ast), inParallel: true,
  //   reportingDiagnosticsTo: &diagnostics,
  //   tracingInferenceIf: nil)
  // }

  private static func loadDefaultStdlibFilepath() -> URL {
    if let path = ProcessInfo.processInfo.environment["HYLO_STDLIB_PATH"] {
      logger.info("Hylo stdlib filepath from HYLO_STDLIB_PATH: \(path)")
      return URL(fileURLWithPath: path)
    }
    else {
      return HyloModule.standardLibrary
    }
  }

  public static func isStdlibDocument(_ uri: DocumentUri) -> Bool {
    let (_, isStdlibDocument) = getStdlibPath(uri)
    return isStdlibDocument
  }

  public static func getStdlibPath(_ uri: DocumentUri) -> (stdlibPath: URL, isStdlibDocument: Bool) {
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


  private func requestDocument(_ uri: DocumentUri, includeCache: Bool) -> DocumentContext {
    let (stdlibPath, isStdlibDocument) = ServerState.getStdlibPath(uri)

    let input = URL.init(string: uri)!
    let inputs: [URL] = if !isStdlibDocument { [input] } else { [] }

    let cacheTask: Task<CachedDocumentResult?, Error> = Task {
      if includeCache && ServerState.useCaching {
        return loadCachedDocumentResult(uri)
      }
      else {
        return nil
      }
    }

    let buildTask = Task {
      return try buildProgram(uri: uri, stdlibPath: stdlibPath, inputs: inputs)
    }

    let request = DocumentBuildRequest(uri: uri, buildTask: buildTask, cacheTask: cacheTask)
    return DocumentContext(request)
  }

  func uriAsFilepath(_ uri: DocumentUri) -> String? {
    guard let url = URL.init(string: uri) else {
      return nil
    }

    return url.path
  }

  private func buildProgram(uri: DocumentUri, stdlibPath: URL, inputs: [URL]) throws -> AnalyzedDocument {
    // let inputs = files.map { URL.init(fileURLWithPath: $0)}
    let importBuiltinModule = false
    let compileSequentially = false

    var diagnostics = DiagnosticSet()
    logger.debug("Build program: \(uri), with stdlibPath: \(stdlibPath), inputs: \(inputs)")

    var t0 = Date()
    var ast = try AST(libraryRoot: stdlibPath)
    let stdlibTime = Date().timeIntervalSince(t0)
    t0 = Date()

    _ = try ast.makeModule(HyloNotificationHandler.productName, sourceCode: sourceFiles(in: inputs),
    builtinModuleAccess: importBuiltinModule, diagnostics: &diagnostics)
    let astTime = Date().timeIntervalSince(t0)
    t0 = Date()

    let p = try TypedProgram(
    annotating: ScopedProgram(ast), inParallel: !compileSequentially,
    reportingDiagnosticsTo: &diagnostics,
    tracingInferenceIf: nil)

    let typeCheckTime = Date().timeIntervalSince(t0)
    logger.debug("Program is built: \(uri), stdlib ast parsing took: \(stdlibTime.milliseconds)ms, program ast parsing took: \(astTime.milliseconds)ms, type checking took: \(typeCheckTime.milliseconds)ms")

    let profiling = DocumentProfiling(stdlibParsing: stdlibTime, ASTParsing: astTime, typeChecking: typeCheckTime)

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

  // public func preloadDocument(_ textDocument: TextDocumentProtocol) -> DocumentBuildRequest {
  //   let uri = DocumentProvider.resolveDocumentUri(textDocument.uri)
  //   return preloadDocument(uri)
  // }

  private func preloadDocument(_ uri: DocumentUri, includeCache: Bool) -> DocumentContext {
    let document = requestDocument(uri, includeCache: includeCache)
    logger.debug("Register opened document: \(uri)")
    documents[uri] = document
    return document
  }

  public func getDocumentContext(_ textDocument: TextDocumentProtocol, includeCache: Bool) -> Result<DocumentContext, InvalidUri> {
    guard let uri = ServerState.validateDocumentUri(textDocument.uri) else {
      return .failure(InvalidUri(textDocument.uri))
    }

    // Check for cached document
    if let request = documents[uri] {
      logger.info("Found cached document: \(uri)")
      return .success(request)
    } else {
      let request = preloadDocument(uri, includeCache: includeCache)
      return .success(request)
    }
  }

  public func getAnalyzedDocument(_ textDocument: TextDocumentProtocol, includeCache: Bool = false) async -> Result<AnalyzedDocument, DocumentError> {
    switch getDocumentContext(textDocument, includeCache: includeCache) {
      case let .failure(error):
        return .failure(.other(error))
      case let .success(context):
        return await resolveDocumentRequest(context.request)
    }
  }

  public func resolveDocumentRequest(_ request: DocumentBuildRequest) async -> Result<AnalyzedDocument, DocumentError> {
    do {
      let document = try await request.buildTask.value
      return .success(document)
    }
    catch let d as DiagnosticSet {
      return .failure(.diagnostics(d))
    }
    catch {
      return .failure(.other(error))
    }
  }


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
}

