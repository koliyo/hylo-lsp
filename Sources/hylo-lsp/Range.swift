import LanguageServerProtocol
import Core

public extension LanguageServerProtocol.Location {
  init(_ range: SourceRange) {
    self.init(uri: range.file.url.path(percentEncoded: false), range: LSPRange(range))
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

