import Core
import FrontEnd
import LanguageServerProtocol
import Foundation
import Logging

struct CompletionResolver {
  let ast: AST
  let program: TypedProgram
  let logger: Logger

  public init(ast: AST, program: TypedProgram, logger: Logger) {
    self.ast = ast
    self.program = program
    self.logger = logger
  }

  // func resolveName(_ id: NameExpr.ID, source: AnyNodeID) -> DefinitionResponse? {
  //   if let d = program.referredDecl[id] {
  //     switch d {
  //     case let .constructor(d, _):
  //       let initializer = ast[d]
  //       let range = ast[d].site
  //       let selectionRange = LSPRange(initializer.introducer.site)
  //       let response = LocationLink(targetUri: range.file.url.absoluteString, targetRange: LSPRange(range), targetSelectionRange: selectionRange)
  //       return .optionC([response])
  //     case let .builtinFunction(f):
  //       logger.warning("builtinFunction: \(f)")
  //       return nil
  //     case .compilerKnownType:
  //       logger.warning("compilerKnownType: \(d)")
  //       return nil
  //     case let .member(m, _, _):
  //       return locationResponse(m, in: ast)
  //     case let .direct(d, args):
  //       logger.debug("direct declaration: \(d), generic args: \(args), name: \(program.name(of: d) ?? "__noname__")")
  //       // let fnNode = ast[d]
  //       // let range = LSPRange(hylocRange: fnNode.site)
  //       return locationResponse(d, in: ast)
  //       // if let fid = FunctionDecl.ID(d) {
  //       //   let f = sourceModule.functions[Function.ID(fid)]!
  //       //   logger.debug("Function: \(f)")
  //       // }
  //     default:
  //       logger.warning("Unknown declaration kind: \(d)")
  //       break
  //     }
  //   }

  //   if let r = resolveExpr(AnyExprID(id)) {
  //     return r
  //   }

  //   if let x = AnyPatternID(source) {
  //     logger.debug("pattern: \(x)")
  //   }

  //   if let s = program.nodeToScope[source] {
  //     logger.debug("scope: \(s)")
  //     if let decls = program.scopeToDecls[s] {
  //       for d in decls {
  //           if let t = program.declType[d] {
  //             logger.debug("decl: \(d), type: \(t)")
  //           }
  //       }
  //     }


  //     if let fn = ast[s] as? FunctionDecl {
  //       logger.debug("TODO: Need to figure out how to get resolved return type of function signature: \(fn.site)")
  //       return nil
  //       // return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO: Need to figure out how to get resolved return type of function signature: \(fn.site)"))
  //     }
  //   }

  //   // return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Internal error, must be able to resolve declaration"))
  //   logger.error("Internal error, must be able to resolve declaration")
  //   return nil
  // }


  public func resolve(_ p: SourcePosition) -> CompletionResponse? {
    logger.debug("Look for symbol definition at position: \(p)")

    guard let id = ast.findNode(p) else {
      logger.warning("Did not find node @ \(p)")
      return nil
    }

    let node = ast[id]
    logger.debug("Found node: \(node), id: \(id)")

    if let d = AnyDeclID(id) {
      logger.info("completion AnyDeclID: \(d)")
      // return locationResponse(d, in: ast)
    }

    if let ex = node as? FunctionCallExpr {
      logger.info("completion FunctionCallExpr: \(ex)")
      // if let n = NameExpr.ID(ex.callee) {
      //   return resolveName(n, source: id)
      // }
    }

    if let n = NameExpr.ID(id) {
      logger.info("completion NameExpr.ID: \(n)")
      // return resolveName(n, source: id)
    }

    logger.warning("Unknown node: \(node)")
    return nil
  }

}
