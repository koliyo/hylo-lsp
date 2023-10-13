// import Foundation

public struct InvalidUri : Error {
  public let uri: String
  public init(_ uri: String) {
    self.uri = uri
  }
}

// /// Validated fully qualified document uri representation
// public struct DocumentUri : Equatable, Sendable, Hashable {
//   public let url: URL

//   public var absoluteString: String { url.absoluteString }
//   public var path: String { url.path(percentEncoded: false) }
//   public var isFileUri: Bool { url.isFileURL }

//   public init(_ uri: String) throws {
//     // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#uri
//     // > Over the wire, it will still be transferred as a string, but this guarantees that the contents of that string can be parsed as a valid URI.

//     guard let url = URL(string: uri) else {
//       throw InvalidUri(uri)
//     }

//     // Make sure the URL is a fully qualified path with scheme
//     if url.scheme == nil {
//       throw InvalidUri(uri)
//     }

//     self.url = url
//   }
// }
