import LanguageServerProtocol
import Core

public extension LanguageServerProtocol.DiagnosticSeverity {
  init(_ level: Core.Diagnostic.Level) {
    switch level {
    case .note:
      self = .information
    case .warning:
      self = .warning
    case .error:
      self = .error
    }
  }
}

public extension LanguageServerProtocol.Diagnostic {
  init(_ diagnostic: Core.Diagnostic) {
    precondition(diagnostic.notes.isEmpty, "TODO: Subdiagnostics")

    self.init(
      range: LSPRange(diagnostic.site),
      severity: DiagnosticSeverity(diagnostic.level),
      code: nil,
      source: nil,
      message: diagnostic.message,
      tags: nil,
      relatedInformation: nil
    )
  }
}

