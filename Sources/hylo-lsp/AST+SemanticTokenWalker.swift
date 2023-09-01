import Core
import FrontEnd
import IR
import LanguageServerProtocol

extension SemanticToken {
  public init(range: SourceRange, type: UInt32, modifiers: UInt32 = 0) {
    let f = range.first()
    let (line, column) = f.lineAndColumn
    let length = range.end.utf16Offset(in: f.file.text) - range.start.utf16Offset(in: f.file.text)
    self.init(line: UInt32(line-1), char: UInt32(column-1), length: UInt32(length), type: type, modifiers: modifiers)
  }
}


extension AST {
  struct SemanticTokenWalker: ASTWalkObserver {
    // var outermostFunctions: [FunctionDecl.ID] = []
    private(set) var tokens: [SemanticToken]
    private let document: DocumentUri

    public init(_ document: DocumentUri) {
      self.document = document
      self.tokens = []
    }

    mutating func willEnter(_ n: AnyNodeID, in ast: AST) -> Bool {
      let node = ast[n]
      let site = node.site

      if let scheme = site.file.url.scheme {
        if scheme == "synthesized" {
          return true
        }
        else if n.kind == TranslationUnit.self && scheme == "file" {
          if site.file.url.absoluteString != document {
            // print("Ignore file: \(site.file.url)")
            return false
          }
          print("Enter file: \(site.file.url)")
        }
      }

      switch node {
      case _ as NamespaceDecl:
        return true
      case let f as FunctionDecl:
        tokens.append(SemanticToken(range: f.identifier!.site, type: TokenType.function.rawValue, modifiers: 0))
        return true
      case let v as VarDecl:
        tokens.append(SemanticToken(range: v.identifier.site, type: TokenType.variable.rawValue, modifiers: 0))
        return true
      case let t as AssociatedTypeDecl:
        tokens.append(SemanticToken(range: t.identifier.site, type: TokenType.type.rawValue, modifiers: 0))
        return true
      case let t as ProductTypeDecl:
        tokens.append(SemanticToken(range: t.identifier.site, type: TokenType.type.rawValue, modifiers: 0))
        return true
      case let c as ConformanceDecl:
        let s = ast[c.subject]
        tokens.append(SemanticToken(range: s.site, type: TokenType.identifier.rawValue, modifiers: 0))
        return true
      default:
        return true
      }
    }
  }

  public func getSematicTokens(_ document: DocumentUri) -> [SemanticToken] {
    print("List symbols in document: \(document)")
    var finder = SemanticTokenWalker(document)

    for m in modules {
      walk(m, notifying: &finder)
    }

    return finder.tokens
  }
}
