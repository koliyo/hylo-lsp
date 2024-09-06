import FrontEnd
import StandardLibrary
import Utils

@main
struct MyApp {

    static func buildProgram() async throws {
      print("async main!")
      var diagnostics: DiagnosticSet = DiagnosticSet()
      let ast = try Host.hostedLibraryAST.get()
      let _ = try TypedProgram(
        annotating: ScopedProgram(ast), inParallel: false,
        reportingDiagnosticsTo: &diagnostics,
        throwOnError: true,
        tracingInferenceIf: nil)
      print("Built standard library")
    }

    static func main() throws {
      Task {
        try await MyApp.buildProgram()
      }
    }
}

