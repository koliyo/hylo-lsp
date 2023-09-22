import Core
import FrontEnd
import IR

extension SourceRepresentable where Part == WhereClause {
  public var introducerSite: SourceRange {
    let whereStart = site.start
    let whereEnd: SourceFile.Index = site.file.text.index(whereStart, offsetBy: 5)
    let indices = whereStart..<whereEnd
    return SourceRange(indices, in: site.file)
  }
}
