import FrontEnd
import Foundation

extension AST {
  internal init(sourceFiles: [SourceFile]) throws {
    self.init(ConditionalCompilationFactors())
    var diagnostics = DiagnosticSet()
    coreLibrary = try makeModule(
      "Hylo",
      sourceCode: sourceFiles,
      builtinModuleAccess: true,
      diagnostics: &diagnostics)

    assert(coreModuleIsLoaded)
    self.coreTraits = .init(self)
  }

  internal init(libraryRoot: URL) throws {
    let sourceFiles = try sourceFiles(in: [libraryRoot])
    try self.init(sourceFiles: sourceFiles)
  }
}
