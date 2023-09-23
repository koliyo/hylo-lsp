import Core
import FrontEnd
import IR

func keywordSite(_ site: SourceRange, len: Int) -> SourceRange {
  let start = site.start
  let end: SourceFile.Index = site.file.text.index(start, offsetBy: len)
  let indices = start..<end
  return SourceRange(indices, in: site.file)
}

extension SourceRepresentable where Part == WhereClause {
  public var introducerSite: SourceRange {
    keywordSite(site, len: 5)
  }
}

extension WhileStmt {
  public var introducerSite: SourceRange {
    keywordSite(site, len: 5)
  }
}


extension ReturnStmt {
  public var introducerSite: SourceRange {
    keywordSite(site, len: 6)
  }
}

extension ConditionalStmt {
  public var introducerSite: SourceRange {
    keywordSite(site, len: 2)
  }
}
