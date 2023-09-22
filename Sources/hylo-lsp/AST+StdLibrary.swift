import Core
import FrontEnd
import IR
import Foundation

extension AST {
  internal init(libraryRoot: URL) throws {
    self.init()
    var diagnostics = DiagnosticSet()
    coreLibrary = try makeModule(
      "Hylo",
      sourceCode: sourceFiles(in: [libraryRoot]),
      builtinModuleAccess: true,
      diagnostics: &diagnostics)
    assert(isCoreModuleLoaded)
  }
}
