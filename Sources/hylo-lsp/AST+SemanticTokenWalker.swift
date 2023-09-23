import Core
import FrontEnd
import IR
import LanguageServerProtocol

extension SemanticToken {
  public init(range: SourceRange, type: UInt32, modifiers: UInt32 = 0) {
    let f = range.first()
    let (line, column) = f.lineAndColumn
    let length = range.end.utf16Offset(in: f.file.text) - range.start.utf16Offset(in: f.file.text)
    self.init(line: UInt32(line-1), char: UInt32(column-1), length: UInt32(length), type: type, modifiers: modifiers)
  }
}


extension AST {
  struct SemanticTokenWalker: ASTWalkObserver {
    // var outermostFunctions: [FunctionDecl.ID] = []
    private(set) var tokens: [SemanticToken]
    private let document: DocumentUri
    private let program: TypedProgram

    public init(_ document: DocumentUri, _ program: TypedProgram) {
      self.document = document
      self.program = program
      self.tokens = []
    }

    mutating func willEnter(_ n: AnyNodeID, in ast: AST) -> Bool {
      let node = ast[n]
      let site = node.site

      if let scheme = site.file.url.scheme {
        if scheme == "synthesized" {
          return true
        }
        else if n.kind == TranslationUnit.self && scheme == "file" {
          if site.file.url.absoluteString != document {
            // logger.debug("Ignore file: \(site.file.url)")
            return false
          }
          logger.debug("Enter file: \(site.file.url)")
        }
      }

      return addDecl(node, in: ast)
    }

    mutating func addSubscriptImpl(_ s: SubscriptImpl.ID, in ast: AST) {
      let s = ast[s]

      // NOTE: introducer + parameter add introducer twice for some reason
      tokens.append(SemanticToken(range: s.introducer.site, type: TokenType.keyword.rawValue))
      // addParameter(s.receiver, in: ast)
      addBody(s.body, in: ast)
    }

    mutating func addDecl(_ node: Node, in ast: AST) -> Bool {

      switch node {
      case _ as TranslationUnit:
        break
      case _ as NamespaceDecl:
        break

      case let d as BindingDecl:
        addBinding(d, in: ast)
        return false
      case let d as InitializerDecl:
        addInitializer(d, in: ast)
        return false
      case let d as SubscriptDecl:
        addSubscript(d, in: ast)
        return false
      case let d as FunctionDecl:
        addFunction(d, in: ast)
        return false
      case _ as VarDecl:
        // NOTE: VarDecl is handled by BindingDecl, which allows binding one or more variables
        break
      case let d as AssociatedTypeDecl:
        tokens.append(SemanticToken(range: d.introducerSite, type: TokenType.keyword.rawValue))
        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue))
      case let d as ProductTypeDecl:

        addAccessModifier(d.accessModifier)
        // tokens.append(SemanticToken(range: d.introducer.site, type: TokenType.keyword.rawValue))

        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue))
        addGenericClause(d.genericClause, in: ast)
        addConformances(d.conformances, in: ast)
      case let d as ExtensionDecl:
        addAccessModifier(d.accessModifier)
        addExpr(d.subject, in: ast)
        addWhereClause(d.whereClause, in: ast)
      case let d as TypeAliasDecl:
        addAccessModifier(d.accessModifier)
        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue))
        addGenericClause(d.genericClause, in: ast)
        addExpr(d.aliasedType, in: ast)
      case let d as ConformanceDecl:
        addAccessModifier(d.accessModifier)
        addExpr(d.subject, in: ast)
        addConformances(d.conformances, in: ast)
        addWhereClause(d.whereClause, in: ast)
      default:
        // print("Unknown node: \(node)")
        break
      }

      return true
    }

    mutating func addDecl(_ decl: AnyDeclID, in ast: AST) -> Bool {
      let node = ast[decl]
      return addDecl(node, in: ast)
    }


    mutating func addBinding(_ d: BindingDecl, in ast: AST) {
      addAttributes(d.attributes, in: ast)
      addAccessModifier(d.accessModifier)
      addOptionalKeyword(d.memberModifier)
      addOptionalKeyword(d.memberModifier)
      addBindingPattern(d.pattern, in: ast)
      addExpr(d.initializer, in: ast)
    }

    mutating func addBindingPattern(_ pattern: BindingPattern.ID, in ast: AST) {
      let p = ast[pattern]
      tokens.append(SemanticToken(range: p.introducer.site, type: TokenType.keyword.rawValue))

      let s = ast[p.subpattern]
      switch s {
      case let s as NamePattern:
        tokens.append(SemanticToken(range: s.site, type: TokenType.variable.rawValue))
        break
      case let s as WildcardPattern:
        tokens.append(SemanticToken(range: s.site, type: TokenType.keyword.rawValue))
        break
      default:
        logger.debug("Unknown pattern: \(s)")
      }

      addExpr(p.annotation, in: ast)
    }

    mutating func addOptionalKeyword<T>(_ keyword: SourceRepresentable<T>?) {
      if let keyword = keyword {
        tokens.append(SemanticToken(range: keyword.site, type: TokenType.keyword.rawValue))
      }
    }

    mutating func addAttributes(_ attributes: [SourceRepresentable<Attribute>], in ast: AST) {
      for a in attributes {
        addAttribute(a.value, in: ast)
      }
    }

    mutating func addAttribute(_ attribute: Attribute, in ast: AST) {
      // TODO
    }

    mutating func addParameters(_ parameters: [ParameterDecl.ID], in ast: AST) {
      for p in parameters {
        addParameter(p, in: ast)
      }
    }

    mutating func addParameter(_ parameter: ParameterDecl.ID?, in ast: AST) {
      guard let parameter = parameter else {
        return
      }

      let p = ast[parameter]
      addLabel(p.label)

      tokens.append(SemanticToken(range: p.identifier.site, type: TokenType.identifier.rawValue))

      if let annotation = p.annotation {
        let a = ast[annotation]
        let c = a.convention
        if c.site.start != c.site.end {
          tokens.append(SemanticToken(range: c.site, type: TokenType.keyword.rawValue))
        }

        addExpr(a.bareType, in: ast)
      }

      addExpr(p.defaultValue, in: ast)
    }


    mutating func addExpr(_ expr: AnyExprID?, in ast: AST) {
      guard let expr = expr else {
        return
      }

      let e = ast[expr]
      switch e {
        case let e as NameExpr:
          // tokens.append(SemanticToken(range: d.site, type: TokenType.type.rawValue))

          switch e.domain {
          case .operand:
            logger.debug("TODO: Domain.operand @ \(e.site)")
          case .implicit:
            // logger.debug("TODO: Domain.implicit @ \(e.site)")
            break
          case let .explicit(id):
            // logger.debug("TODO: Domain.explicit: \(id) @ \(e.site)")
            addExpr(id, in: ast)
          case .none:
            break
          }

          // TODO: Full name handling: stem, labels, notation, introducer
          // TODO: Name type should simply be `identifier`? Otherwise we need to pass paramter if it is `type`, `function`, etc
          tokens.append(SemanticToken(range: e.name.site, type: TokenType.type.rawValue))
          addArguments(e.arguments, in: ast)

        case let e as TupleTypeExpr:

          for el in e.elements {

            addLabel(el.label)
            addExpr(el.type, in: ast)
          }

        case let e as NumericLiteralExpr:
          tokens.append(SemanticToken(range: e.site, type: TokenType.number.rawValue))

        case let e as FunctionCallExpr:
          addExpr(e.callee, in: ast)
          addArguments(e.arguments, in: ast)
        case let e as SubscriptCallExpr:
          addExpr(e.callee, in: ast)
          addArguments(e.arguments, in: ast)
        case let e as SequenceExpr:
          addExpr(e.head, in: ast)
          for el in e.tail {
            let op = ast[el.operator]
            tokens.append(SemanticToken(range: op.site, type: TokenType.operator.rawValue))
            addExpr(el.operand, in: ast)
          }

        case let e as LambdaExpr:
          addFunction(ast[e.decl], in: ast)

        case let e as ConditionalExpr:
          tokens.append(SemanticToken(range: e.introducerSite, type: TokenType.keyword.rawValue))
          addConditions(e.condition, in: ast)
          addExpr(e.success, in: ast)
          addExpr(e.failure, in: ast)

        case let e as InoutExpr:
          tokens.append(SemanticToken(range: e.operatorSite, type: TokenType.operator.rawValue))
          addExpr(e.subject, in: ast)

        case let e as TupleMemberExpr:
          addExpr(e.tuple, in: ast)
          tokens.append(SemanticToken(range: e.index.site, type: TokenType.number.rawValue))

        case let e as TupleExpr:
          for el in e.elements {
            addLabel(el.label)
            addExpr(el.value, in: ast)
          }

        case let e as LambdaTypeExpr:
          addOptionalKeyword(e.receiverEffect)
          addExpr(e.environment, in: ast)
          for p in e.parameters {
            addLabel(p.label)
            let pt = ast[p.type]
            addOptionalKeyword(pt.convention)
            addExpr(pt.bareType, in: ast)
          }
          addExpr(e.output, in: ast)

        default:
          logger.debug("Unknown expr: \(e)")
      }
    }

    mutating func addConditions(_ conditions: [ConditionItem], in ast: AST) {
      for c in conditions {
        switch c {
          case let .expr(e):
            addExpr(e, in: ast)
          case let .decl(d):
            addBinding(ast[d], in: ast)
        }
      }
    }

    mutating func addArguments(_ arguments: [LabeledArgument], in ast: AST) {
      for a in arguments {
        addLabel(a.label)
        addExpr(a.value, in: ast)
      }
    }


    mutating func addSubscript(_ d: SubscriptDecl, in ast: AST) {
      addAttributes(d.attributes, in: ast)
      addAccessModifier(d.accessModifier)
      addOptionalKeyword(d.memberModifier)
      tokens.append(SemanticToken(range: d.introducer.site, type: TokenType.function.rawValue))
      if let identifier = d.identifier {
        tokens.append(SemanticToken(range: identifier.site, type: TokenType.function.rawValue))
      }

      addGenericClause(d.genericClause, in: ast)
      addParameters(d.parameters, in: ast)
      addExpr(d.output, in: ast)

      for i in d.impls {
        addSubscriptImpl(i, in: ast)
      }
    }

    mutating func addInitializer(_ d: InitializerDecl, in ast: AST) {
      addAttributes(d.attributes, in: ast)
      addAccessModifier(d.accessModifier)
      tokens.append(SemanticToken(range: d.introducer.site, type: TokenType.function.rawValue))
      addGenericClause(d.genericClause, in: ast)
      addParameters(d.parameters, in: ast)
      addStatements(d.body, in: ast)
    }

    mutating func addFunction(_ d: FunctionDecl, in ast: AST) {
      addAttributes(d.attributes, in: ast)
      addAccessModifier(d.accessModifier)
      addOptionalKeyword(d.memberModifier)
      addOptionalKeyword(d.notation)
      tokens.append(SemanticToken(range: d.introducerSite, type: TokenType.keyword.rawValue))
      if let identifier = d.identifier {
        tokens.append(SemanticToken(range: identifier.site, type: TokenType.function.rawValue))
      }

      addGenericClause(d.genericClause, in: ast)
      addParameters(d.parameters, in: ast)
      addOptionalKeyword(d.receiverEffect)
      addExpr(d.output, in: ast)
      addBody(d.body, in: ast)
    }

    mutating func addBody(_ body: FunctionBody?, in ast: AST) {
      switch body {
      case nil:
        break
      case let .expr(e):
        addExpr(e, in: ast)
      case let .block(b):
        addStatements(b, in: ast)
      }
    }

    mutating func addStatements(_ b: BraceStmt.ID?, in ast: AST) {
      guard let b = b else {
        return
      }

      addStatements(ast[b].stmts, in: ast)
    }

    mutating func addStatements(_ statements: [AnyStmtID], in ast: AST) {
      for s in statements {
        addStatement(s, in: ast)
      }
    }

    mutating func addStatement(_ statement: AnyStmtID?, in ast: AST) {
      guard let statement = statement else {
        return
      }

      let s = ast[statement]

      switch s {
        case let s as ExprStmt:
          addExpr(s.expr, in: ast)
        case let s as ReturnStmt:
          tokens.append(SemanticToken(range: s.introducerSite, type: TokenType.type.rawValue))
          addExpr(s.value, in: ast)
        case let s as DeclStmt:
          _ = addDecl(s.decl, in: ast)
          break
        case let s as WhileStmt:
          tokens.append(SemanticToken(range: s.introducerSite, type: TokenType.keyword.rawValue))
          addConditions(s.condition, in: ast)
          addStatements(s.body, in: ast)
        case let s as AssignStmt:
          addExpr(s.left, in: ast)
          addExpr(s.right, in: ast)
        case let s as ConditionalStmt:
          tokens.append(SemanticToken(range: s.introducerSite, type: TokenType.keyword.rawValue))
          addConditions(s.condition, in: ast)
          addStatements(s.success, in: ast)
          addStatement(s.failure, in: ast)
        default:
          print("Unknown statement: \(s)")
      }
    }

    mutating func addWhereClause(_ whereClause: SourceRepresentable<WhereClause>?, in ast: AST) {
      guard let whereClause = whereClause else {
        return
      }

      tokens.append(SemanticToken(range: whereClause.introducerSite, type: TokenType.keyword.rawValue))

      for c in whereClause.value.constraints {
        switch c.value {
        case let .equality(n, e):
          let n = ast[n]
          tokens.append(SemanticToken(range: n.site, type: TokenType.type.rawValue))
          addExpr(e, in: ast)
          break
        case let .conformance(n, _):
          let n = ast[n]
          tokens.append(SemanticToken(range: n.site, type: TokenType.type.rawValue))
          break
        default:
          break
        }
      }
    }

    mutating func addLabel(_ label: SourceRepresentable<Identifier>?) {
      if let label = label {
        tokens.append(SemanticToken(range: label.site, type: TokenType.label.rawValue))
      }
    }

    mutating func addAccessModifier(_ accessModifier: SourceRepresentable<AccessModifier>) {
      // Check for empty site
      if accessModifier.site.start != accessModifier.site.end {
        tokens.append(SemanticToken(range: accessModifier.site, type: TokenType.keyword.rawValue))
      }
    }

    mutating func addConformances(_ conformances: [NameExpr.ID], in ast: AST) {
      for id in conformances {
        let n = ast[id]
        tokens.append(SemanticToken(range: n.site, type: TokenType.type.rawValue))
      }
    }

    mutating func addGenericClause(_ genericClause: SourceRepresentable<GenericClause>?, in ast: AST) {
      if let genericClause = genericClause {
        addGenericClause(genericClause.value, in: ast)
      }
    }


    mutating func addGenericClause(_ genericClause: GenericClause, in ast: AST) {
      addWhereClause(genericClause.whereClause, in: ast)

      for id in genericClause.parameters {
        let p = ast[id]
        tokens.append(SemanticToken(range: p.identifier.site, type: TokenType.type.rawValue))
        addConformances(p.conformances, in: ast)

        if let id = p.defaultValue {
          let defaultValue = ast[id]
          tokens.append(SemanticToken(range: defaultValue.site, type: TokenType.type.rawValue))
        }
      }
    }
  }

  public func getSematicTokens(_ document: DocumentUri, _ program: TypedProgram) -> [SemanticToken] {
    logger.debug("List symbols in document: \(document)")
    var finder = SemanticTokenWalker(document, program)

    for m in modules {
      // logger.debug("Walk module: \(m)")
      walk(m, notifying: &finder)
    }

    return finder.tokens
  }
}
