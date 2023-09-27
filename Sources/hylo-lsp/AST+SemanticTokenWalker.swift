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
      addIntroducer(s.introducer)
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
        addIntroducer(d.introducerSite)
        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue))
      case let d as ProductTypeDecl:

        addAccessModifier(d.accessModifier)
        addIntroducer(d.introducerSite)
        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue))
        addGenericClause(d.genericClause, in: ast)
        addConformances(d.conformances, in: ast)
      case let d as ExtensionDecl:
        addAccessModifier(d.accessModifier)
        addIntroducer(d.introducerSite)
        addExpr(d.subject, in: ast)
        addWhereClause(d.whereClause, in: ast)
      case let d as TypeAliasDecl:
        addAccessModifier(d.accessModifier)
        addIntroducer(d.introducerSite)
        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue))
        addGenericClause(d.genericClause, in: ast)
        addExpr(d.aliasedType, in: ast)
      case let d as ConformanceDecl:
        addAccessModifier(d.accessModifier)
        addIntroducer(d.introducerSite)
        addExpr(d.subject, in: ast)
        addConformances(d.conformances, in: ast)
        addWhereClause(d.whereClause, in: ast)

      case let d as TraitDecl:
        addAccessModifier(d.accessModifier)
        addIntroducer(d.introducerSite)
        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue))
        addConformances(d.refinements, in: ast)

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
      addIntroducer(d.memberModifier)
      addIntroducer(d.memberModifier)
      addBindingPattern(d.pattern, in: ast)
      addExpr(d.initializer, in: ast)
    }

    mutating func addPattern(_ pattern: AnyPatternID, in ast: AST) {
      let p = ast[pattern]

      switch p {
      case let p as NamePattern:
        tokens.append(SemanticToken(range: p.site, type: TokenType.variable.rawValue))
      case let p as WildcardPattern:
        addIntroducer(p.site)
      case let p as BindingPattern:
        addIntroducer(p.introducer)
        addPattern(p.subpattern, in: ast)
        addExpr(p.annotation, in: ast)
      case let p as TuplePattern:
        for e in p.elements {
          if let label = e.label {
            tokens.append(SemanticToken(range: label.site, type: TokenType.label.rawValue))
          }

          addPattern(e.pattern, in: ast)
        }

      default:
        logger.debug("Unknown pattern: \(p)")
      }
    }

    mutating func addIntroducer<T>(_ site: SourceRepresentable<T>?) {
      if let site = site {
        addIntroducer(site.site)
      }
    }

    mutating func addIntroducer(_ site: SourceRange) {
      tokens.append(SemanticToken(range: site, type: TokenType.keyword.rawValue))
    }

    mutating func addBindingPattern(_ pattern: BindingPattern.ID, in ast: AST) {
      let p = ast[pattern]
      addIntroducer(p.introducer)

      addPattern(p.subpattern, in: ast)
      addExpr(p.annotation, in: ast)
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
          addIntroducer(c.site)
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

        case let e as BooleanLiteralExpr:
          addIntroducer(e.site)
        case let e as NumericLiteralExpr:
          tokens.append(SemanticToken(range: e.site, type: TokenType.number.rawValue))
        case let e as StringLiteralExpr:
          tokens.append(SemanticToken(range: e.site, type: TokenType.string.rawValue))

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
          addIntroducer(e.introducerSite)
          addConditions(e.condition, in: ast)
          addExpr(e.success, in: ast)
          addIntroducer(e.failure.introducerSite)
          addExpr(e.failure.value, in: ast)

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
          addIntroducer(e.receiverEffect)
          addExpr(e.environment, in: ast)
          for p in e.parameters {
            addLabel(p.label)
            let pt = ast[p.type]
            addIntroducer(pt.convention)
            addExpr(pt.bareType, in: ast)
          }
          addExpr(e.output, in: ast)

        case let e as MatchExpr:
          addIntroducer(e.introducerSite)
          addExpr(e.subject, in: ast)

          for c in e.cases {
            addMatchCase(c, in: ast)
          }

        case let e as CastExpr:
          addIntroducer(e.introducerSite)
          addExpr(e.left, in: ast)
          addExpr(e.right, in: ast)

        case _ as WildcardExpr:
          break

        case let e as ExistentialTypeExpr:
          addIntroducer(e.introducerSite)
          addConformances(e.traits, in: ast)
          addWhereClause(e.whereClause, in: ast)

        case let e as RemoteExpr:
          addIntroducer(e.introducerSite)
          addIntroducer(e.convention)
          addExpr(e.operand, in: ast)

        default:
          logger.debug("Unknown expr: \(e)")
      }
    }

    mutating func addMatchCase(_ matchCase: MatchCase.ID, in ast: AST) {
      let c = ast[matchCase]
      addPattern(c.pattern, in: ast)
      addExpr(c.condition, in: ast)

      switch c.body {
        case let .expr(e):
          addExpr(e, in: ast)
        case let .block(b):
          addStatements(b, in: ast)
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
      addIntroducer(d.memberModifier)
      addIntroducer(d.introducer)
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
      addIntroducer(d.introducer)
      addGenericClause(d.genericClause, in: ast)
      addParameters(d.parameters, in: ast)
      addStatements(d.body, in: ast)
    }

    mutating func addFunction(_ d: FunctionDecl, in ast: AST) {
      addAttributes(d.attributes, in: ast)
      addAccessModifier(d.accessModifier)
      addIntroducer(d.memberModifier)
      addIntroducer(d.notation)
      addIntroducer(d.introducerSite)
      if let identifier = d.identifier {
        tokens.append(SemanticToken(range: identifier.site, type: TokenType.function.rawValue))
      }

      addGenericClause(d.genericClause, in: ast)
      addParameters(d.parameters, in: ast)
      addIntroducer(d.receiverEffect)
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
        case let s as WhileStmt:
          addIntroducer(s.introducerSite)
          addConditions(s.condition, in: ast)
          addStatements(s.body, in: ast)
        case let s as DoWhileStmt:
          addIntroducer(s.introducerSite)
          addStatements(s.body, in: ast)
          addIntroducer(s.condition.introducerSite)
          addExpr(s.condition.value, in: ast)
        case let s as AssignStmt:
          addExpr(s.left, in: ast)
          addExpr(s.right, in: ast)
        case let s as ConditionalStmt:
          addIntroducer(s.introducerSite)
          addConditions(s.condition, in: ast)
          addStatements(s.success, in: ast)
          if let elseClause = s.failure {
            addIntroducer(elseClause.introducerSite)
            addStatement(elseClause.value, in: ast)
          }
        case let s as YieldStmt:
          addIntroducer(s.introducerSite)
          addExpr(s.value, in: ast)
        case let s as BraceStmt:
          addStatements(s.stmts, in: ast)
        case let s as DiscardStmt:
          addExpr(s.expr, in: ast)
        default:
          print("Unknown statement: \(s)")
      }
    }

    mutating func addWhereClause(_ whereClause: SourceRepresentable<WhereClause>?, in ast: AST) {
      guard let whereClause = whereClause else {
        return
      }

      addIntroducer(whereClause.value.introducerSite)

      for c in whereClause.value.constraints {
        switch c.value {
        case let .equality(n, e):
          let n = ast[n]
          tokens.append(SemanticToken(range: n.site, type: TokenType.type.rawValue))
          addExpr(e, in: ast)
        case let .conformance(n, _):
          let n = ast[n]
          tokens.append(SemanticToken(range: n.site, type: TokenType.type.rawValue))
        case let .value(e):
          addExpr(e, in: ast)
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
        addIntroducer(accessModifier.site)
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
