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
    private var binding: BindingDecl?

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

      switch node {
      case let d as BindingDecl:
        binding = d
        return true
      case _ as NamespaceDecl:
        return true
      case let d as InitializerDecl:
        addAttributes(d.attributes, in: ast)
        addAccessModifier(d.accessModifier)
        tokens.append(SemanticToken(range: d.introducer.site, type: TokenType.function.rawValue))
        addGenericClause(d.genericClause, in: ast)
        return true
      case let d as SubscriptDecl:
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

        return true
      case let d as FunctionDecl:
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

        return true
      case let d as VarDecl:
        guard let binding = binding else {
          return true
        }

        addAttributes(binding.attributes, in: ast)
        addAccessModifier(binding.accessModifier)
        addOptionalKeyword(binding.memberModifier)
        addOptionalKeyword(binding.memberModifier)
        let p = ast[binding.pattern]
        tokens.append(SemanticToken(range: p.introducer.site, type: TokenType.keyword.rawValue))

        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.variable.rawValue))
        addBindingPattern(binding.pattern, in: ast)
        addExpr(binding.initializer, in: ast)

        self.binding = nil
        return true
      case let d as AssociatedTypeDecl:
        tokens.append(SemanticToken(range: d.introducerSite, type: TokenType.keyword.rawValue))
        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue))
        return true
      case let d as ProductTypeDecl:
        // guard let binding = binding else {
        //   return true
        // }


        addAccessModifier(d.accessModifier)
        // let p = ast[binding.pattern]
        // tokens.append(SemanticToken(range: p.introducer.site, type: TokenType.keyword.rawValue))

        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue))
        addGenericClause(d.genericClause, in: ast)
        addConformances(d.conformances, in: ast)
        return true
      case let d as ExtensionDecl:
        addAccessModifier(d.accessModifier)
        addExpr(d.subject, in: ast)
        addWhereClause(d.whereClause, in: ast)
        return true
      case let d as TypeAliasDecl:
        addAccessModifier(d.accessModifier)
        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue))
        addGenericClause(d.genericClause, in: ast)
        addExpr(d.aliasedType, in: ast)

        return true
      case let d as ConformanceDecl:
        addAccessModifier(d.accessModifier)
        addExpr(d.subject, in: ast)
        addConformances(d.conformances, in: ast)
        addWhereClause(d.whereClause, in: ast)

        return true
      default:
        return true
      }
    }

    mutating func addBindingPattern(_ pattern: BindingPattern.ID, in ast: AST) {
      let pattern = ast[pattern]
      // tokens.append(SemanticToken(range: pattern.introducer.site, type: TokenType.keyword.rawValue))
      // TODO: subpattern
      addExpr(pattern.annotation, in: ast)
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

    mutating func addParameter(_ parameter: ParameterDecl.ID, in ast: AST) {
      let p = ast[parameter]
      if let label = p.label {
        tokens.append(SemanticToken(range: label.site, type: TokenType.keyword.rawValue))
      }

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
        case let d as NameExpr:
          tokens.append(SemanticToken(range: d.site, type: TokenType.type.rawValue))
        case let d as TupleTypeExpr:

          for e in d.elements {

            if let l = e.label {
              tokens.append(SemanticToken(range: l.site, type: TokenType.keyword.rawValue))
            }

            addExpr(e.type, in: ast)
          }
        default:
          logger.debug("unknown expr: \(e)")
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
