import Foundation
import LanguageServerProtocol
import HyloModule
import Core
import FrontEnd
import Logging

protocol TextDocumentProtocol {
  var uri: DocumentUri { get }
}

extension TextDocumentIdentifier : TextDocumentProtocol {}
extension TextDocumentItem : TextDocumentProtocol {}
extension VersionedTextDocumentIdentifier : TextDocumentProtocol {}

actor DocumentProvider {
  private var documents: [DocumentUri:DocumentBuildRequest]
  // public let logger: Logger

  public static let defaultStdlibFilepath: URL = loadDefaultStdlibFilepath()

  public init() {
    // self.logger = logger
    documents = [:]
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
        // let relUrl = URL(string: url.absoluteString, relativeTo: it)!
        // logger.info("it: \(it), relUrl: \(relUrl.relativePath), path: \(relUrl.path)")
        // uri = state.stdlibFilepath.appending(component: relUrl.relativePath).absoluteString
        return (it, true)
      }

      it = it.deletingLastPathComponent()
    }

    return (defaultStdlibFilepath, false)
  }


  private func requestDocument(_ uri: DocumentUri) -> DocumentBuildRequest {
    let (stdlibPath, isStdlibDocument) = DocumentProvider.getStdlibPath(uri)

    let inputs: [URL] = if !isStdlibDocument { [URL.init(string: uri)!] } else { [] }

    let task = Task {
      return try buildProgram(uri: uri, stdlibPath: stdlibPath, inputs: inputs)
    }

    return DocumentBuildRequest(uri: uri, task: task)
  }

  private func buildProgram(uri: DocumentUri, stdlibPath: URL, inputs: [URL]) throws -> Document {
    // let inputs = files.map { URL.init(fileURLWithPath: $0)}
    let importBuiltinModule = false
    let compileSequentially = false

    var diagnostics = DiagnosticSet()
    logger.debug("Build program: \(uri), with stdlibPath: \(stdlibPath), inputs: \(inputs)")

    var ast = try AST(libraryRoot: stdlibPath)
    _ = try ast.makeModule(HyloNotificationHandler.productName, sourceCode: sourceFiles(in: inputs),
    builtinModuleAccess: importBuiltinModule, diagnostics: &diagnostics)

    let p = try TypedProgram(
    annotating: ScopedProgram(ast), inParallel: !compileSequentially,
    reportingDiagnosticsTo: &diagnostics,
    tracingInferenceIf: nil)
    logger.debug("Program is built: \(uri)")

    return Document(uri: uri, ast: ast, program: p)
  }


  public static func resolveDocumentUrl(_ uri: DocumentUri) -> URL {

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
      // TODO: Relative path is not generally supported, potenitially using rootUri, or single workspace entry
      let fm = FileManager.default
      let p = NSString.path(withComponents: [fm.currentDirectoryPath, uri])
      return URL(fileURLWithPath: p)
    }
  }

  public static func resolveDocumentUri(_ uri: DocumentUri) -> DocumentUri {
    return resolveDocumentUrl(uri).absoluteString
  }

  // public func preloadDocument(_ textDocument: TextDocumentProtocol) -> DocumentBuildRequest {
  //   let uri = DocumentProvider.resolveDocumentUri(textDocument.uri)
  //   return preloadDocument(uri)
  // }

  private func preloadDocument(_ uri: DocumentUri) -> DocumentBuildRequest {
    let document = requestDocument(uri)
    logger.debug("Register opened document: \(uri)")
    documents[uri] = document
    return document
  }

  public func getDocument(_ textDocument: TextDocumentProtocol) async -> Result<Document, DocumentError> {
    let uri = DocumentProvider.resolveDocumentUri(textDocument.uri)

    // Check for cached document
    if let request = documents[uri] {
      logger.info("Found cached document: \(uri)")
      return await resolveDocumentRequest(request)
    } else {
      let request = preloadDocument(uri)
      return await resolveDocumentRequest(request)
    }
  }

  public func resolveDocumentRequest(_ request: DocumentBuildRequest) async -> Result<Document, DocumentError> {
    do {
      let document = try await request.task.value
      return .success(document)
    }
    catch let d as DiagnosticSet {
      return .failure(.diagnostics(d))
    }
    catch {
      return .failure(.other(error))
    }
  }
}
