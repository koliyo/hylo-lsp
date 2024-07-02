import Foundation
import FrontEnd
import LanguageServerProtocol
import Logging

struct SemanticTokensWalker {
  public let document: DocumentUri
  public let translationUnit: TranslationUnit
  public let ast: AST
  private let logger: Logger
  private(set) var tokens: [SemanticToken]

  public init(document: DocumentUri, translationUnit: TranslationUnit, ast: AST, logger: Logger) {
    self.document = document
    self.translationUnit = translationUnit
    self.ast = ast
    self.tokens = []
    self.logger = logger
  }

  public mutating func walk() -> [SemanticToken] {
    precondition(tokens.isEmpty)
    addMembers(translationUnit.decls)
    return tokens
  }

  mutating func addSubscriptImpl(_ s: SubscriptImpl.ID) {
    let s = ast[s]

    // NOTE: introducer + parameter add introducer twice for some reason
    addIntroducer(s.introducer)
    // addParameter(s.receiver)
    addBody(s.body)
  }

  mutating func addDecl(_ decl: AnyDeclID) {
    let node = ast[decl]
    addDecl(node)
  }

  mutating func addDecl(_ node: Node) {

    switch node {
    case let d as NamespaceDecl:
      addNamespace(d)
    case let d as BindingDecl:
      addBinding(d)
    case let d as InitializerDecl:
      addInitializer(d)
    case let d as SubscriptDecl:
      addSubscript(d)
    case let d as FunctionDecl:
      addFunction(d)
    case let d as MethodDecl:
      addMethod(d)
    case let d as OperatorDecl:
      addOperator(d)
    case _ as VarDecl:
      // NOTE: VarDecl is handled by BindingDecl, which allows binding one or more variables
      break
    case let d as AssociatedTypeDecl:
      addAssociatedType(d)
    case let d as ProductTypeDecl:
      addProductType(d)
    case let d as ExtensionDecl:
      addExtension(d)
    case let d as TypeAliasDecl:
      addTypeAlias(d)
    case let d as ConformanceDecl:
      addConformance(d)
    case let d as TraitDecl:
      addTrait(d)
    case let d as GenericParameterDecl:
      addGenericParameter(d)
    default:
      logger.warning("Unknown node: \(node)")
      // printStackTrace()
    }
  }

  mutating func addNamespace(_ d: NamespaceDecl) {
    addAccessModifier(d.accessModifier)
    addIntroducer(d.introducerSite)
    addToken(range: d.identifier.site, type: .namespace)

    addMembers(d.members)
  }

  mutating func addBinding(_ d: BindingDecl, skipAccessModifier: Bool = false) {
    addAttributes(d.attributes)
    if !skipAccessModifier {
      addAccessModifier(d.accessModifier)
    }
    addIntroducer(d.memberModifier)
    addBindingPattern(d.pattern)
    addExpr(d.initializer)
  }

  mutating func addPattern(_ pattern: AnyPatternID) {
    let p = ast[pattern]

    switch p {
    case let p as NamePattern:
      addToken(range: p.site, type: .variable)
    case let p as WildcardPattern:
      addIntroducer(p.site)
    case let p as BindingPattern:
      addIntroducer(p.introducer)
      addPattern(p.subpattern)
      addExpr(p.annotation)
    case let p as TuplePattern:
      for e in p.elements {
        if let label = e.label {
          addToken(range: label.site, type: .label)
        }

        addPattern(e.pattern)
      }

    default:
      logger.debug("Unknown pattern: \(p)")
    }
  }

  mutating func addToken(range: SourceRange, type: TokenType, modifiers: UInt32 = 0) {
    tokens.append(SemanticToken(range: range, type: type, modifiers: modifiers))
  }

  mutating func addIntroducer<T>(_ site: SourceRepresentable<T>?) {
    if let site = site {
      addIntroducer(site.site)
    }
  }

  mutating func addIntroducer(_ site: SourceRange) {
    addToken(range: site, type: .keyword)
  }

  mutating func addBindingPattern(_ pattern: BindingPattern.ID) {
    let p = ast[pattern]
    addIntroducer(p.introducer)

    addPattern(p.subpattern)
    addExpr(p.annotation, typeHint: .type)
  }

  mutating func addAttributes(_ attributes: [SourceRepresentable<Attribute>]) {
    for a in attributes {
      addAttribute(a.value)
    }
  }

  mutating func addAttribute(_ attribute: Attribute) {
    addToken(range: attribute.name.site, type: .function)

    for a in attribute.arguments {
      addExpr(a.value)
    }
  }

  mutating func addParameters(_ parameters: [ParameterDecl.ID]) {
    for p in parameters {
      addParameter(p)
    }
  }

  mutating func addParameter(_ parameter: ParameterDecl.ID?) {
    guard let parameter = parameter else {
      return
    }

    let p = ast[parameter]
    addLabel(p.label)

    // NOTE: We are currently using .identifier instead of .parameter here,
    // for astetic purposes. This is similar to swift tokens
    addToken(range: p.identifier.site, type: .identifier)

    if let annotation = p.annotation {
      let a = ast[annotation]
      let c = a.convention
      if c.site.start != c.site.end {
        addIntroducer(c.site)
      }

      addExpr(a.bareType, typeHint: .type)
    }

    addExpr(p.defaultValue)
  }

#if false
  // https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide#standard-token-types-and-modifiers
  func tokenType(_ d: AnyDeclID) -> TokenType {
    switch d.kind {
      case ProductTypeDecl.self: .type
      case TypeAliasDecl.self: .type
      case AssociatedTypeDecl.self: .type
      case ExtensionDecl.self: .type
      case ConformanceDecl.self: .type
      case GenericParameterDecl.self: .typeParameter
      case TraitDecl.self: .type
      case InitializerDecl.self: .function
      case SubscriptDecl.self: .function
      case FunctionDecl.self: .function
      case MethodDecl.self: .function
      case VarDecl.self: .variable
      case BindingDecl.self: .variable
      case ParameterDecl.self: .parameter
      case ModuleDecl.self: .namespace
      default: .unknown
    }
  }

  func tokenType(_ d: DeclReference?) -> TokenType {
    switch d {
      case .constructor:
        .function
      case .builtinFunction:
        .function
      case .compilerKnownType:
        .type
      case .builtinType:
        .type
      case let .direct(id, _):
        tokenType(id)
      case let .member(id, _, _):
        tokenType(id)
      case .builtinModule:
        .namespace
      case nil:
        .unknown
    }
  }
#endif

  mutating func addNameExpr(_ e: NameExpr, typeHint: TokenType?) {
    switch e.domain {
      case .operand:
        logger.debug("TODO: Domain.operand @ \(e.site)")
      case .implicit:
        // logger.debug("TODO: Domain.implicit @ \(e.site)")
        break
      case let .explicit(id):
        // logger.debug("TODO: Domain.explicit: \(id) @ \(e.site)")
        addExpr(id)
      case .none:
        break
      }

      // let n = NameExpr.ID(expr)!
      // let d = program.referredDecl[n]
      // let t = tokenType(d)
      // if d != nil && t == .unknown {
      //   logger.warning("Unknown decl reference: \(d!)")
      // }

      let t = typeHint ?? TokenType.variable

      addToken(range: e.name.site, type: t)
      addTypeArguments(e.arguments)
  }

  mutating func addTypeArguments(_ arguments: [LabeledArgument]) {
    for a in arguments {
      addLabel(a.label)
      addExpr(a.value, typeHint: .typeParameter)
    }
  }


  mutating func addExpr(_ expr: AnyExprID?, typeHint: TokenType? = nil) {
    guard let expr = expr else {
      return
    }

    let e = ast[expr]
    switch e {
      case let e as NameExpr:
        // addToken(range: e.site, type: .variable)
        addNameExpr(e, typeHint: typeHint)
      case let e as TupleTypeExpr:

        for el in e.elements {

          addLabel(el.label)
          addExpr(el.type)
        }

      case let e as BooleanLiteralExpr:
        addIntroducer(e.site)
      case let e as NumericLiteralExpr:
        addToken(range: e.site, type: .number)
      case let e as StringLiteralExpr:
        addToken(range: e.site, type: .string)

      case let e as FunctionCallExpr:
        addExpr(e.callee, typeHint: .function)
        addArguments(e.arguments)
      case let e as SubscriptCallExpr:
        addExpr(e.callee, typeHint: .function)
        addArguments(e.arguments)
      case let e as SequenceExpr:
        addExpr(e.head)
        for el in e.tail {
          let op = ast[el.operator]
          addToken(range: op.site, type: .operator)
          addExpr(el.operand)
        }

      case let e as LambdaExpr:
        addFunction(ast[e.decl])

      case let e as ConditionalExpr:
        addIntroducer(e.introducerSite)
        addConditions(e.condition)
        addExpr(e.success)
        addIntroducer(e.failure.introducerSite)
        addExpr(e.failure.value)

      case let e as InoutExpr:
        addToken(range: e.operatorSite, type: .operator)
        addExpr(e.subject, typeHint: typeHint)

      case let e as TupleMemberExpr:
        addExpr(e.tuple)
        addToken(range: e.index.site, type: .number)

      case let e as TupleExpr:
        for el in e.elements {
          addLabel(el.label)
          addExpr(el.value)
        }

      case let e as ArrowTypeExpr:
        addIntroducer(e.receiverEffect)
        addExpr(e.environment)
        for p in e.parameters {
          addLabel(p.label)
          let pt = ast[p.type]
          addIntroducer(pt.convention)
          addExpr(pt.bareType, typeHint: .type)
        }
        addExpr(e.output, typeHint: .type)

      case let e as MatchExpr:
        addIntroducer(e.introducerSite)
        addExpr(e.subject)

        for c in e.cases {
          addMatchCase(c)
        }

      case let e as CastExpr:
        addIntroducer(e.introducerSite)
        addExpr(e.left)
        addExpr(e.right, typeHint: .type)

      case _ as WildcardExpr:
        break

      case let e as ExistentialTypeExpr:
        addIntroducer(e.introducerSite)
        addConformances(e.traits)
        addWhereClause(e.whereClause)

      case let e as RemoteTypeExpr:
        addIntroducer(e.introducerSite)
        addIntroducer(e.convention)
        addExpr(e.operand)

      case let e as PragmaLiteralExpr:
        addToken(range: e.site, type: .identifier)

      case let e as ConformanceLensExpr:
        addExpr(e.subject, typeHint: .type)
        addExpr(e.lens, typeHint: .type)

      default:
        logger.debug("Unknown expr: \(e)")
    }
  }

  mutating func addMatchCase(_ matchCase: MatchCase.ID) {
    let c = ast[matchCase]
    addPattern(c.pattern)
    addExpr(c.condition)

    switch c.body {
      case let .expr(e):
        addExpr(e)
      case let .block(b):
        addStatements(b)
    }
  }

  mutating func addConditions(_ conditions: [ConditionItem]) {
    for c in conditions {
      switch c {
        case let .expr(e):
          addExpr(e)
        case let .decl(d):
          addBinding(ast[d])
      }
    }
  }

  mutating func addArguments(_ arguments: [LabeledArgument]) {
    for a in arguments {
      addLabel(a.label)
      addExpr(a.value)
    }
  }

  mutating func addExtension(_ d: ExtensionDecl) {
    addAccessModifier(d.accessModifier)
    addIntroducer(d.introducerSite)
    addExpr(d.subject)
    addWhereClause(d.whereClause)
    addMembers(d.members)
  }

  mutating func addAssociatedType(_ d: AssociatedTypeDecl) {
    addIntroducer(d.introducerSite)
    addToken(range: d.identifier.site, type: .type)
    addConformances(d.conformances)
    addWhereClause(d.whereClause)
    addExpr(d.defaultValue)
  }

  mutating func addTypeAlias(_ d: TypeAliasDecl) {
    addAccessModifier(d.accessModifier)
    addIntroducer(d.introducerSite)
    addToken(range: d.identifier.site, type: .type)
    addGenericClause(d.genericClause)
    addExpr(d.aliasedType)
  }


  mutating func addConformance(_ d: ConformanceDecl) {
    addAccessModifier(d.accessModifier)
    addIntroducer(d.introducerSite)
    addExpr(d.subject)
    addConformances(d.conformances)
    addWhereClause(d.whereClause)
    addMembers(d.members)
  }

  mutating func addGenericParameter(_ d: GenericParameterDecl) {
    // addToken(range: d.identifier.site, type: .typeParameter)
    // addConformances(d.conformances)
    // addExpr(d.defaultValue)
  }

  mutating func addTrait(_ d: TraitDecl) {
    addAccessModifier(d.accessModifier)
    addIntroducer(d.introducerSite)
    addToken(range: d.identifier.site, type: .type)
    addConformances(d.bounds)
    addMembers(d.members)
  }

  mutating func addProductType(_ d: ProductTypeDecl) {
    addAccessModifier(d.accessModifier)
    addIntroducer(d.introducerSite)
    addToken(range: d.identifier.site, type: .type)
    addGenericClause(d.genericClause)
    addConformances(d.conformances)
    addMembers(d.members)
  }


  mutating func addMembers(_ members: [AnyDeclID]) {
    for m in members {
      addDecl(m)
    }
  }

  mutating func addSubscript(_ d: SubscriptDecl) {
    addAttributes(d.attributes)
    addAccessModifier(d.accessModifier)
    addIntroducer(d.memberModifier)
    addIntroducer(d.introducer)
    if let identifier = d.identifier {
      addToken(range: identifier.site, type: .function)
    }

    addGenericClause(d.genericClause)
    addParameters(d.parameters)
    addExpr(d.output, typeHint: .type)

    for i in d.impls {
      addSubscriptImpl(i)
    }
  }



  mutating func addInitializer(_ d: InitializerDecl) {
    addAttributes(d.attributes)
    addAccessModifier(d.accessModifier)
    addIntroducer(d.introducer)
    addGenericClause(d.genericClause)
    addParameters(d.parameters)
    addStatements(d.body)
  }

  mutating func addFunction(_ d: FunctionDecl) {
    addAttributes(d.attributes)
    addAccessModifier(d.accessModifier)
    addIntroducer(d.memberModifier)
    addIntroducer(d.notation)
    addIntroducer(d.introducerSite)
    if let identifier = d.identifier {
      addToken(range: identifier.site, type: .function)
    }

    addGenericClause(d.genericClause)
    addParameters(d.parameters)
    addIntroducer(d.receiverEffect)
    addExpr(d.output, typeHint: .type)
    addBody(d.body)
  }

  mutating func addOperator(_ d: OperatorDecl) {
    addAccessModifier(d.accessModifier)
    addIntroducer(d.introducerSite)
    addIntroducer(d.notation)
    addIntroducer(d.introducerSite)
    addToken(range: d.name.site, type: .operator)

    if let precedenceGroup = d.precedenceGroup {
      addToken(range: precedenceGroup.site, type: .identifier)
    }
  }

  mutating func addMethod(_ d: MethodDecl) {
    addAttributes(d.attributes)
    addAccessModifier(d.accessModifier)
    addIntroducer(d.notation)
    addIntroducer(d.introducerSite)
    addToken(range: d.identifier.site, type: .function)

    addGenericClause(d.genericClause)
    addParameters(d.parameters)
    addExpr(d.output, typeHint: .type)

    for i in d.impls {
      let i = ast[i]
      addIntroducer(i.introducer)
      // addParameter(i.receiver)
      addBody(i.body)
    }
  }

  mutating func addBody(_ body: FunctionBody?) {
    switch body {
    case nil:
      break
    case let .expr(e):
      addExpr(e)
    case let .block(b):
      addStatements(b)
    }
  }

  mutating func addStatements(_ b: BraceStmt.ID?) {
    guard let b = b else {
      return
    }

    addStatements(ast[b].stmts)
  }

  mutating func addStatements(_ statements: [AnyStmtID]) {
    for s in statements {
      addStatement(s)
    }
  }

  mutating func addStatement(_ statement: AnyStmtID?) {
    guard let statement = statement else {
      return
    }

    let s = ast[statement]

    switch s {
      case let s as ExprStmt:
        addExpr(s.expr)
      case let s as ReturnStmt:
        addToken(range: s.introducerSite, type: .keyword)
        addExpr(s.value)
      case let s as DeclStmt:
        addDecl(s.decl)
      case let s as WhileStmt:
        addIntroducer(s.introducerSite)
        addConditions(s.condition)
        addStatements(s.body)
      case let s as ForStmt:
        addIntroducer(s.introducerSite)
        addBinding(ast[s.binding], skipAccessModifier: true)
        addIntroducer(s.domain.introducerSite)
        addExpr(s.domain.value)
        if let filter = s.filter {
          addIntroducer(filter.introducerSite)
          addExpr(filter.value)
        }
        addStatements(s.body)

      case let s as DoWhileStmt:
        addIntroducer(s.introducerSite)
        addStatements(s.body)
        addIntroducer(s.condition.introducerSite)
        addExpr(s.condition.value)
      case let s as AssignStmt:
        addExpr(s.left)
        addExpr(s.right)
      case let s as ConditionalStmt:
        addIntroducer(s.introducerSite)
        addConditions(s.condition)
        addStatements(s.success)
        if let elseClause = s.failure {
          addIntroducer(elseClause.introducerSite)
          addStatement(elseClause.value)
        }
      case let s as YieldStmt:
        addIntroducer(s.introducerSite)
        addExpr(s.value)
      case let s as BraceStmt:
        addStatements(s.stmts)
      case let s as DiscardStmt:
        addExpr(s.expr)
      default:
        logger.warning("Unknown statement: \(s)")
    }
  }

  mutating func addWhereClause(_ whereClause: SourceRepresentable<WhereClause>?) {
    guard let whereClause = whereClause else {
      return
    }

    addIntroducer(whereClause.value.introducerSite)

    for c in whereClause.value.constraints {
      switch c.value {
      case let .equality(n, e):
        let n = ast[n]
        addToken(range: n.site, type: .type)
        addExpr(e)
      case let .bound(n, _):
        let n = ast[n]
        addToken(range: n.site, type: .type)
      case let .value(e):
        addExpr(e)
      }
    }
  }

  mutating func addLabel(_ label: SourceRepresentable<Identifier>?) {
    if let label = label {
      addToken(range: label.site, type: .label)
    }
  }

  mutating func addAccessModifier(_ accessModifier: SourceRepresentable<AccessModifier>) {
    // Check for empty site
    if accessModifier.site.start != accessModifier.site.end {
      addIntroducer(accessModifier.site)
    }
  }

  mutating func addConformances(_ conformances: [NameExpr.ID]) {
    for id in conformances {
      let n = ast[id]
      addToken(range: n.site, type: .type)
    }
  }

  mutating func addGenericClause(_ genericClause: SourceRepresentable<GenericClause>?) {
    if let genericClause = genericClause {
      addGenericClause(genericClause.value)
    }
  }


  mutating func addGenericClause(_ genericClause: GenericClause) {
    addWhereClause(genericClause.whereClause)

    for id in genericClause.parameters {
      let p = ast[id]
      addToken(range: p.identifier.site, type: .type)
      addConformances(p.conformances)

      if let id = p.defaultValue {
        let defaultValue = ast[id]
        addToken(range: defaultValue.site, type: .type)
      }
    }
  }
}

extension AST {

  public func getSematicTokens(_ document: DocumentUri, logger: Logger) -> [SemanticToken] {
    logger.debug("List semantic tokens in document: \(document)")

    guard let translationUnit = findTranslationUnit(document) else {
      logger.error("Failed to locate translation unit: \(document)")
      return []
    }

    var walker = SemanticTokensWalker(document: document, translationUnit: self[translationUnit], ast: self, logger: logger)
    return walker.walk()
  }
}
