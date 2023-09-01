import Core
import FrontEnd
import IR
import LanguageServerProtocol

extension AST {
  struct DocumentSymbolWalker: ASTWalkObserver {
    // var outermostFunctions: [FunctionDecl.ID] = []
    private(set) var symbols: [AnyDeclID]
    private let document: DocumentUri


    public init(_ document: DocumentUri) {
      self.document = document
      self.symbols = []
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

      if n.kind == NamespaceDecl.self || n.kind == TranslationUnit.self {
        return true
      }


      if n.kind == BindingDecl.self {
        return true
      }

      // if n.kind == FunctionDecl.self || n.kind == VarDecl.self {
      if let d = AnyDeclID(n) {
        print("Found symbol node: \(d), site: \(site)")
        symbols.append(d)
        return false
      }

      // print("Ignore node: \(n)")
      return true
    }
  }

  public func listSymbols(_ document: DocumentUri) -> [AnyDeclID] {
    print("List symbols in document: \(document)")
    var finder = DocumentSymbolWalker(document)

    for m in modules {
      walk(m, notifying: &finder)
    }

    return finder.symbols
  }
}
