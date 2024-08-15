import LanguageServerProtocol
import FrontEnd

public extension LanguageServerProtocol.Location {
  init(_ range: SourceRange) {
    self.init(uri: range.file.url.path, range: LSPRange(range))
  }
}

public extension LanguageServerProtocol.LSPRange {
  init(_ range: SourceRange) {
    self.init(start: Position(range.start), end: Position(range.end))
  }
}

public extension LanguageServerProtocol.Position {
  init(_ pos: SourcePosition) {
    let (line, column) = pos.lineAndColumn
    self.init(line: line-1, character: column-1)
  }
}
