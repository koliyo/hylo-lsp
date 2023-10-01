import LanguageServerProtocol
import Core
import FrontEnd

public struct Document {
  public let uri: DocumentUri
  public let program: TypedProgram
  public let ast: AST

  public init(uri: DocumentUri, ast: AST, program: TypedProgram) {
    self.uri = uri
    self.ast = ast
    self.program = program
  }
}

public struct DocumentBuildRequest {
  public let uri: DocumentUri
  public var task: Task<Document, Error>

  public init(uri: DocumentUri, task: Task<Document, Error>) {
    self.uri = uri
    self.task = task
  }
}

public enum DocumentError : Error {
  case diagnostics(DiagnosticSet)
  case other(Error)
}
