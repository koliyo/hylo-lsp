import LanguageServerProtocol
import Core

public extension LanguageServerProtocol.Location {
  init(_ range: SourceRange) {
    self.init(uri: range.file.url.path, range: LSPRange(range))
  }
}

public extension LanguageServerProtocol.LSPRange {
  init(_ range: SourceRange) {
    let first = range.first()
    let last: SourcePosition

    if let l = range.last() {
      let incLast = range.file.text.index(after: l.index)
      last = SourcePosition(incLast, in: l.file)
    }
    else {
      last = SourcePosition(range.file.text.endIndex, in: range.file)
    }

    self.init(start: Position(first), end: Position(last))
  }
}

public extension LanguageServerProtocol.Position {
  init(_ pos: SourcePosition) {
    let (line, column) = pos.lineAndColumn
    self.init(line: line-1, character: column-1)
  }
}
