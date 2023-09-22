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
        for _ in d.attributes {
          // TODO
        }

        tokens.append(SemanticToken(range: d.accessModifier.site, type: TokenType.keyword.rawValue, modifiers: 0))

        tokens.append(SemanticToken(range: d.introducer.site, type: TokenType.function.rawValue, modifiers: 0))
        addGenericClause(d.genericClause, in: ast)
        return true
      case let d as FunctionDecl:

        for _ in d.attributes {
          // TODO
        }

        tokens.append(SemanticToken(range: d.accessModifier.site, type: TokenType.keyword.rawValue, modifiers: 0))
        if let s = d.memberModifier {
          tokens.append(SemanticToken(range: s.site, type: TokenType.keyword.rawValue, modifiers: 0))
        }
        if let s = d.notation {
          tokens.append(SemanticToken(range: s.site, type: TokenType.keyword.rawValue, modifiers: 0))
        }
        tokens.append(SemanticToken(range: d.introducerSite, type: TokenType.keyword.rawValue, modifiers: 0))
        if let identifier = d.identifier {
          tokens.append(SemanticToken(range: identifier.site, type: TokenType.function.rawValue, modifiers: 0))
        }
        addGenericClause(d.genericClause, in: ast)

        if let s = d.receiverEffect {
          tokens.append(SemanticToken(range: s.site, type: TokenType.keyword.rawValue, modifiers: 0))
        }

        return true
      case let d as VarDecl:
        guard let binding = binding else {
          return true
        }

        for _ in binding.attributes {
          // TODO
        }


        tokens.append(SemanticToken(range: binding.accessModifier.site, type: TokenType.keyword.rawValue, modifiers: 0))

        if let s = binding.memberModifier {
          tokens.append(SemanticToken(range: s.site, type: TokenType.keyword.rawValue, modifiers: 0))
        }

        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.variable.rawValue, modifiers: 0))
        self.binding = nil
        return true
      case let d as AssociatedTypeDecl:
        tokens.append(SemanticToken(range: d.introducerSite, type: TokenType.keyword.rawValue, modifiers: 0))
        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue, modifiers: 0))
        return true
      case let d as ProductTypeDecl:
        tokens.append(SemanticToken(range: d.accessModifier.site, type: TokenType.keyword.rawValue, modifiers: 0))
        tokens.append(SemanticToken(range: d.identifier.site, type: TokenType.type.rawValue, modifiers: 0))
        addGenericClause(d.genericClause, in: ast)
        addConformances(d.conformances, in: ast)
        return true
      case let d as ConformanceDecl:
        let s = ast[d.subject]
        logger.debug("conformance: \(d)")
        // tokens.append(SemanticToken(range: d.site, type: TokenType.identifier.rawValue, modifiers: 0))
        return true
      default:
        return true
      }
    }

    mutating func addConformances(_ conformances: [NameExpr.ID], in ast: AST) {
      for id in conformances {
        let n = ast[id]
        tokens.append(SemanticToken(range: n.site, type: TokenType.type.rawValue, modifiers: 0))
      }
    }

    mutating func addGenericClause(_ genericClause: SourceRepresentable<GenericClause>?, in ast: AST) {
      if let genericClause = genericClause {
        addGenericClause(genericClause.value, in: ast)
      }
    }


    mutating func addGenericClause(_ genericClause: GenericClause, in ast: AST) {
      if let s = genericClause.whereClause {
        tokens.append(SemanticToken(range: s.site, type: TokenType.keyword.rawValue, modifiers: 0))
      }

      for id in genericClause.parameters {
        let p = ast[id]
        tokens.append(SemanticToken(range: p.identifier.site, type: TokenType.type.rawValue, modifiers: 0))
        addConformances(p.conformances, in: ast)

        if let id = p.defaultValue {
          let defaultValue = ast[id]
          tokens.append(SemanticToken(range: defaultValue.site, type: TokenType.type.rawValue, modifiers: 0))
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
