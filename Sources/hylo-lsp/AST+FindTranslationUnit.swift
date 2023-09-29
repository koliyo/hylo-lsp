import Foundation
import Core
import FrontEnd
import IR
import LanguageServerProtocol

extension AST {
  private struct TranslationUnitFinder: ASTWalkObserver {
    // var outermostFunctions: [FunctionDecl.ID] = []
    let query: DocumentUri
    private(set) var match: TranslationUnit.ID?


    public init(_ query: DocumentUri) {
      self.query = query
    }

    mutating func willEnter(_ n: AnyNodeID, in ast: AST) -> Bool {
      let node = ast[n]
      let site = node.site

      if node is TranslationUnit {
        if site.file.url.absoluteString == query {
          match = TranslationUnit.ID(n)
        }
        return false
      }

      return true
    }
  }

  public func findTranslationUnit(_ url: DocumentUri) -> TranslationUnit.ID? {
    var finder = TranslationUnitFinder(url)
    for m in modules {
      walk(m, notifying: &finder)
      if finder.match != nil {
        break
      }
    }
    return finder.match
  }
}
