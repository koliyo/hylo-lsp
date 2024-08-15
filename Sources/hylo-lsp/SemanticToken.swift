import FrontEnd
import LanguageServerProtocol

extension SemanticToken {
  public init(range: SourceRange, type: TokenType, modifiers: UInt32 = 0) {
    let f = range.start
    let (line, column) = f.lineAndColumn
    let length = range.endIndex.utf16Offset(in: f.file.text) - range.startIndex.utf16Offset(in: f.file.text)
    self.init(
      line: UInt32(line - 1), char: UInt32(column - 1), length: UInt32(length), type: type.rawValue,
      modifiers: modifiers)
  }
}
