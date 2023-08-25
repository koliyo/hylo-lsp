import Foundation
import LanguageClient
// import ProcessEnv
import LanguageServerProtocol
import JSONRPC
import UniSocket
import JSONRPC_DataChannel_UniSocket

import Core
import FrontEnd
import IR


func write(_ input: AST, to output: URL) throws {
  let encoder = JSONEncoder().forAST
  try encoder.encode(input).write(to: output, options: .atomic)
}

var inferenceTracingSite: SourceLine?

/// Returns `true` if type inference related to `n`, which is in `p`, whould be traced.
private func shouldTraceInference(_ n: AnyNodeID, _ p: TypedProgram) -> Bool {
  if let s = inferenceTracingSite {
    return s.bounds.contains(p[n].site.first())
  } else {
    return false
  }
}

// let transforms : ModulePassList? = nil
// var outputType: OutputType = .binary

/// Returns `program` lowered to Val IR, accumulating diagnostics in `log` and throwing if an
/// error occured.
///
/// Mandatory IR passes are applied unless `self.outputType` is `.rawIR`.
private func lower(
  program: TypedProgram, reportingDiagnosticsTo log: inout DiagnosticSet
) throws -> IR.Program {
  var loweredModules: [ModuleDecl.ID: IR.Module] = [:]
  for d in program.ast.modules {
    loweredModules[d] = try lower(d, in: program, reportingDiagnosticsTo: &log)
  }

  let ir = IR.Program(syntax: program, modules: loweredModules)
  // if let t = transforms {
  //   for p in t.elements { ir.applyPass(p) }
  // }
  return ir
}

/// Returns `m`, which is `program`, lowered to Val IR, accumulating diagnostics in `log` and
/// throwing if an error occured.
///
/// Mandatory IR passes are applied unless `self.outputType` is `.rawIR`.
private func lower(
  _ m: ModuleDecl.ID, in program: TypedProgram, reportingDiagnosticsTo log: inout DiagnosticSet
) throws -> IR.Module {
  let ir = try IR.Module(lowering: m, in: program, reportingDiagnosticsTo: &log)
  // if outputType != .rawIR {
  //   try ir.applyMandatoryPasses(reportingDiagnosticsTo: &log)
  // }
  return ir
}

  // let noStandardLibrary = false
  // let productName = "factorial"
  // var ast = noStandardLibrary ? AST.coreModule : AST.standardLibrary
  // let inputs = [factorialUrl]
  // let importBuiltinModule = false
  // // let shouldTraceInference = true
  // let compileSequentially = false
  // var diagnostics = DiagnosticSet()

  // // The module whose Val files were given on the command-line
  // let sourceAst = try ast.makeModule(
  //   productName, sourceCode: sourceFiles(in: inputs),
  //   builtinModuleAccess: importBuiltinModule, diagnostics: &diagnostics)

  // // try write(ast, to: URL.init(fileURLWithPath:"factorial.ast.json"))

  // let program = try TypedProgram(
  //   annotating: ScopedProgram(ast), inParallel: !compileSequentially,
  //   reportingDiagnosticsTo: &diagnostics,
  //   tracingInferenceIf: shouldTraceInference)

  // var ir = try lower(program: program, reportingDiagnosticsTo: &diagnostics)
  // let sourceModule = ir.modules[sourceAst]!

  // let f = try SourceFile(contentsOf: factorialUrl)
  // let p = SourcePosition(line: 9, column: 15, in: f)
  // if let id = ast.findNode(p) {
  //   let s = program.nodeToScope[id]!
  //   let s2 = program.nodeToScope[s]!
  //   let node = ast[id]
  //   print("Found node: \(node), id: \(id)")
  //   // print("scope: \(ast[s])")
  //   // print("scope2: \(ast[s2])")
  //   // let t = program.exprType[AnyExprID(id.rawValue)]

  //   // if let decls = program.scopeToDecls[s] {
  //   //   for d in decls {
  //   //     print("d: \(d)")
  //   //   }
  //   // }

  //   // if let x = AnyExprID(id) {
  //   //   let t = program.exprType[x]
  //   //   print("type: \(t!)")
  //   // }

  //   if let n = NameExpr.ID(id) {
  //     // let d = program[n].referredDecl
  //     let d = program.referredDecl[n]

  //     // print("d: \(d)")
  //     if case let .direct(d, args) = d {
  //       print("d: \(d), generic args: \(args)")
  //       if let fid = FunctionDecl.ID(d) {
  //         let f = sourceModule.functions[Function.ID(fid)]!
  //         // print("Function: \(f)")
  //         print("Function: \(program.name(of: d)!)")
  //       }

  //     }
  //   }


  //   // if let fid = FunctionDecl.ID(s2) {
  //   //   // let params = sourceModule.loweredParameters(of: fid)
  //   //   // print("params: \(params)")
  //   //   let fid = Function.ID(fid)
  //   //   print("fid: \(fid)")
  //   //   let f = sourceModule.functions[fid]!
  //   //   print("Function: \(f)")

  //   //   for b in f.blocks {
  //   //     print("Block: \(b)")

  //   //     // for i in b.instructions {
  //   //     //   print("Instruction: \(i)")
  //   //     //   print("  at: \(i.site)")
  //   //     // }
  //   //   }
  //   // }




  //   // module[Function.ID] -> Function
  //   // module[Block.ID] -> Block
  // }
