import Core
import FrontEnd
import IR

extension AST {
  struct NodeFinder: ASTWalkObserver {
    // var outermostFunctions: [FunctionDecl.ID] = []
    let query: SourcePosition
    private(set) var match: AnyNodeID?


    public init(_ query: SourcePosition) {
      self.query = query
    }

    mutating func willEnter(_ n: AnyNodeID, in ast: AST) -> Bool {
      let node = ast[n]
      let site = node.site

      if let scheme = site.file.url.scheme {
        if scheme == "synthesized" {
          // print("Enter: \(site), id: \(n)")
          return true
        }
      }

      // NOTE: We should cache root node per file

      if site.file != query.file {
        return false
      }

      if site.start > query.index {
        return false
      }

      // We have a match, but nested children may be more specific
      if site.end >= query.index {
        match = n
        // print("Found match: \(n)")
        return true
      }

      return true
    }
  }

  public func findNode(_ position: SourcePosition) -> AnyNodeID? {
    var finder = NodeFinder(position)
    for m in modules {
      walk(m, notifying: &finder)
      if finder.match != nil {
        break
      }
    }

    return finder.match
  }
}
