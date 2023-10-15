import LanguageServerProtocol
import Core
import FrontEnd
import Foundation

public struct DocumentProfiling {
  public let stdlibParsing: TimeInterval
  public let ASTParsing: TimeInterval
  public let typeChecking: TimeInterval
}

public struct AnalyzedDocument {
  public let uri: DocumentUri
  public let program: TypedProgram
  public let ast: AST
  public let profiling: DocumentProfiling

  public init(uri: DocumentUri, ast: AST, program: TypedProgram, profiling: DocumentProfiling) {
    self.uri = uri
    self.ast = ast
    self.program = program
    self.profiling = profiling
  }
}

public struct CachedDocumentResult: Codable {
  public var uri: DocumentUri
  public var symbols: DocumentSymbolResponse?
  public var semanticTokens: SemanticTokensResponse?
}


public actor DocumentContext {
  public var uri: DocumentUri { request.uri }
  public let request: DocumentBuildRequest
  private var cachedDocumentResult: Result<CachedDocumentResult?, Error>?
  private var analyzedDocument: Result<AnalyzedDocument, Error>?

  public init(_ request: DocumentBuildRequest) {
    self.request = request
    Task {
      await self.monitorTasks()
    }
  }

  public func pollAnalyzedDocument() -> Result<AnalyzedDocument, Error>? {
    return analyzedDocument
  }

  public func pollCachedDocumentResult() -> Result<CachedDocumentResult?, Error>? {
    return cachedDocumentResult
  }

  public func getAnalyzedDocument() async -> Result<AnalyzedDocument, Error> {
    do {
      let doc = try await request.buildTask.value
      return .success(doc)
    }
    catch {
      return .failure(error)
    }
  }

  public func getAST() async -> Result<AST, Error> {
    do {
      let ast = try await request.astTask.value
      return .success(ast)
    }
    catch {
      return .failure(error)
    }
  }

  public func getCachedDocumentResult() async -> Result<CachedDocumentResult?, Error> {
    do {
      let doc = try await request.cacheTask.value
      return .success(doc)
    }
    catch {
      return .failure(error)
    }
  }

  private func monitorTasks() {

    Task {
      self.analyzedDocument = await getAnalyzedDocument()
    }

    Task {
      self.cachedDocumentResult = await getCachedDocumentResult()
    }
  }
}

public struct DocumentBuildRequest {
  public let uri: DocumentUri
  public let cacheTask: Task<CachedDocumentResult?, Error>
  public let astTask: Task<AST, Error>
  public let buildTask: Task<AnalyzedDocument, Error>

  public init(uri: DocumentUri, astTask: Task<AST, Error>, buildTask: Task<AnalyzedDocument, Error>, cacheTask: Task<CachedDocumentResult?, Error>) {
    self.uri = uri
    self.astTask = astTask
    self.buildTask = buildTask
    self.cacheTask = cacheTask
  }
}

public enum DocumentError : Error {
  case diagnostics(DiagnosticSet)
  case other(Error)
}

