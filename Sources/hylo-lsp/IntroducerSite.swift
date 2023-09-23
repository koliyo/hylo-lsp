import Core
import FrontEnd
import IR

extension SourceRepresentable where Part == WhereClause {
  public var introducerSite: SourceRange {
    let start = site.start
    let end: SourceFile.Index = site.file.text.index(start, offsetBy: 5)
    let indices = start..<end
    return SourceRange(indices, in: site.file)
  }
}

extension Stmt {
  func keywordSite(_ len: Int) -> SourceRange {
    let start = site.start
    let end: SourceFile.Index = site.file.text.index(start, offsetBy: len)
    let indices = start..<end
    return SourceRange(indices, in: site.file)
  }
}

extension WhileStmt {
  public var introducerSite: SourceRange {
    keywordSite(5)
  }
}


extension ReturnStmt {
  public var introducerSite: SourceRange {
    keywordSite(6)
  }
}

extension ConditionalStmt {
  public var introducerSite: SourceRange {
    keywordSite(2)
  }
}
