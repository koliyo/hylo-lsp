import LanguageServerProtocol
import Core
import FrontEnd

public struct Document {
  public let uri: DocumentUri
  public var task: Task<(AST, TypedProgram), Error>

  public init(uri: DocumentUri, ast: AST, program: TypedProgram) {
    self.uri = uri
    self.task = Task { (ast, program) }
  }

  public init(uri: DocumentUri, task: Task<(AST, TypedProgram), Error>) {
    self.uri = uri
    self.task = task
  }
}

// public struct DocumentCache {
//   public let documents: [DocumentUri:Document] = [:]
// }
