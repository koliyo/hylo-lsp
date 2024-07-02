import FrontEnd
import LanguageServerProtocol
import Foundation
import Logging

struct DefinitionResolver {
  let ast: AST
  let program: TypedProgram
  let logger: Logger

  public init(ast: AST, program: TypedProgram, logger: Logger) {
    self.ast = ast
    self.program = program
    self.logger = logger
  }


  public func nameRange(of d: AnyDeclID, in ast: AST) -> SourceRange? {
    // if let e = self.ast[d] as? SingleEntityDecl { return Name(stem: e.baseName) }

    switch d.kind {
    case FunctionDecl.self:
      return ast[FunctionDecl.ID(d)!].identifier!.site
    case InitializerDecl.self:
      return ast[InitializerDecl.ID(d)!].site
    case MethodImpl.self:
      return ast[MethodDecl.ID(d)!].identifier.site
    case SubscriptImpl.self:
      return ast[SubscriptDecl.ID(d)!].site
    case VarDecl.self:
      return ast[VarDecl.ID(d)!].identifier.site
    case ParameterDecl.self:
      return ast[ParameterDecl.ID(d)!].identifier.site
    default:
      return nil
    }
  }



  func locationLink<T>(_ d: T, in ast: AST) -> LocationLink where T: NodeIDProtocol {
    let range = ast[d].site
    let targetUri = range.file.url
    var selectionRange = LSPRange(range)

    if let d = AnyDeclID(d) {
      selectionRange = LSPRange(nameRange(of: d, in: ast) ?? range)
    }

    return LocationLink(targetUri: targetUri.absoluteString, targetRange: LSPRange(range), targetSelectionRange: selectionRange)
  }

  func locationResponse<T>(_ d: T, in ast: AST) -> DefinitionResponse where T: NodeIDProtocol{
    let location = locationLink(d, in: ast)
    return .optionC([location])
  }


  func resolveName(_ id: NameExpr.ID, source: AnyNodeID) -> DefinitionResponse? {
    if let d = program.referredDecl[id] {
      switch d {
      case let .constructor(d, _):
        let initializer = ast[d]
        let range = ast[d].site
        let selectionRange = LSPRange(initializer.introducer.site)
        let response = LocationLink(targetUri: range.file.url.absoluteString, targetRange: LSPRange(range), targetSelectionRange: selectionRange)
        return .optionC([response])
      case let .builtinFunction(f):
        logger.warning("builtinFunction: \(f)")
        return nil
      case .compilerKnownType:
        logger.warning("compilerKnownType: \(d)")
        return nil
      case let .member(m, _, _):
        return locationResponse(m, in: ast)
      case let .direct(d, args):
        logger.debug("direct declaration: \(d), generic args: \(args), name: \(program.name(of: d) ?? "__noname__")")
        // let fnNode = ast[d]
        // let range = LSPRange(hylocRange: fnNode.site)
        return locationResponse(d, in: ast)
        // if let fid = FunctionDecl.ID(d) {
        //   let f = sourceModule.functions[Function.ID(fid)]!
        //   logger.debug("Function: \(f)")
        // }
      default:
        logger.warning("Unknown declaration kind: \(d)")
        break
      }
    }

    if let r = resolveExpr(AnyExprID(id)) {
      return r
    }

    if let x = AnyPatternID(source) {
      logger.debug("pattern: \(x)")
    }

    if let s = program.nodeToScope[source] {
      logger.debug("scope: \(s)")
      if let decls = program.scopeToDecls[s] {
        for d in decls {
            if let t = program.declType[d] {
              logger.debug("decl: \(d), type: \(t)")
            }
        }
      }


      if let fn = ast[s] as? FunctionDecl {
        logger.debug("TODO: Need to figure out how to get resolved return type of function signature: \(fn.site)")
        return nil
        // return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "TODO: Need to figure out how to get resolved return type of function signature: \(fn.site)"))
      }
    }

    // return .failure(JSONRPCResponseError(code: ErrorCodes.InternalError, message: "Internal error, must be able to resolve declaration"))
    logger.error("Internal error, must be able to resolve declaration")
    return nil
  }

  func resolveExpr(_ id: AnyExprID) -> DefinitionResponse? {
    if let t = program.exprType[id] {
      switch t.base {
      case let u as ProductType:
        return locationResponse(u.decl, in: ast)
      case let u as TypeAliasType:
        return locationResponse(u.decl, in: ast)
      case let u as AssociatedTypeType:
        return locationResponse(u.decl, in: ast)
      case let u as GenericTypeParameterType:
        return locationResponse(u.decl, in: ast)
      case let u as NamespaceType:
        return locationResponse(u.decl, in: ast)
      case let u as TraitType:
        return locationResponse(u.decl, in: ast)
      default:
        logger.warning("Unknown expression type: \(t)")
        return nil
      }
    }

    return nil
  }


  public func resolve(_ p: SourcePosition) -> DefinitionResponse? {
    logger.debug("Look for symbol definition at position: \(p)")

    guard let id = ast.findNode(p) else {
      logger.warning("Did not find node @ \(p)")
      return nil
    }

    let node = ast[id]
    logger.debug("Found node: \(node), id: \(id)")

    if let d = AnyDeclID(id) {
      return locationResponse(d, in: ast)
    }

    if let ex = node as? FunctionCallExpr {
      if let n = NameExpr.ID(ex.callee) {
        return resolveName(n, source: id)
      }
    }

    if let n = NameExpr.ID(id) {
      return resolveName(n, source: id)
    }

    logger.warning("Unknown node: \(node)")
    return nil
  }

}
