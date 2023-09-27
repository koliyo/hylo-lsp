import LanguageServerProtocol
import Core
import FrontEnd

public struct Document {
  public let uri: DocumentUri
  public var task: Task<TypedProgram, Error>

  public init(uri: DocumentUri, program: TypedProgram) {
    self.uri = uri
    self.task = Task { program }
  }

  public init(uri: DocumentUri, task: Task<TypedProgram, Error>) {
    self.uri = uri
    self.task = task
  }
}

// public struct DocumentCache {
//   public let documents: [DocumentUri:Document] = [:]
// }
