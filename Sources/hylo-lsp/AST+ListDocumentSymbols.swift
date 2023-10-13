import Core
import FrontEnd
import LanguageServerProtocol

struct DocumentSymbolWalker {
  let document: AnalyzedDocument
  let translationUnit: TranslationUnit
  private(set) var symbols: [DocumentSymbol]

  var ast: AST { document.ast }
  var program: TypedProgram { document.program }

  public init(document: AnalyzedDocument, translationUnit: TranslationUnit) {
    self.document = document
    self.translationUnit = translationUnit
    self.symbols = []
  }

  public mutating func walk() -> [DocumentSymbol] {
    precondition(symbols.isEmpty)
    return getSymbols(translationUnit.decls) ?? []
  }

  func getSymbols(_ ids: [AnyDeclID]) -> [DocumentSymbol]? {
    let symbols = ids.flatMap{ getSymbols($0) ?? [] }
    return if symbols.isEmpty { nil } else { symbols }
  }

  func getSymbols(_ id: AnyDeclID) -> [DocumentSymbol]? {
    let node = ast[id]
    // logger.debug("Found symbol node: \(id), site: \(node.site)")

    switch node {
    case let d as NamespaceDecl:
      return [getSymbol(d)]
    case let d as ProductTypeDecl:
      return [getSymbol(d)]
    case let d as ExtensionDecl:
      return [getSymbol(d)]
    case let d as ConformanceDecl:
      return [getSymbol(d)]
    case let d as AssociatedTypeDecl:
      return [getSymbol(d)]
    case let d as TypeAliasDecl:
      return [getSymbol(d)]
    case let d as TraitDecl:
      return [getSymbol(d)]
    case let d as FunctionDecl:
      return [getSymbol(d)]
    case let d as MethodDecl:
      return getSymbols(d)
    case let d as InitializerDecl:
      return [getSymbol(d)]
    case let d as SubscriptDecl:
      return [getSymbol(d)]
    case let d as BindingDecl:
      return getSymbols(d)
    default:
      logger.warning("Ignored declaration node: \(node)")
      return nil
    }
  }

  func getSymbol(_ d: NamespaceDecl) -> DocumentSymbol {
    let range = LSPRange(d.site)
    let selectionRange = LSPRange(d.identifier.site)

    return DocumentSymbol(
      name: d.identifier.value,
      detail: nil,
      kind: SymbolKind.namespace,
      range: range,
      selectionRange: selectionRange,
      children: getSymbols(d.members)
    )
  }

  func getSymbol(_ d: ProductTypeDecl) -> DocumentSymbol {
    let range = LSPRange(d.site)
    let selectionRange = LSPRange(d.identifier.site)

    return DocumentSymbol(
      name: d.identifier.value,
      detail: nil,
      kind: SymbolKind.struct,
      range: range,
      selectionRange: selectionRange,
      children: getSymbols(d.members)
    )
  }


  func getSymbol(_ d: ExtensionDecl) -> DocumentSymbol {
    let range = LSPRange(d.site)
    let sub = ast[d.subject]
    let type = program.exprType[d.subject]
    let selectionRange = LSPRange(sub.site)

    let name = if let type = type { name(of: type ) } else { "extension" }

    return DocumentSymbol(
      name: name,
      detail: nil,
      kind: SymbolKind.struct,
      range: range,
      selectionRange: selectionRange,
      children: getSymbols(d.members)
    )
  }

  func getSymbol(_ d: AssociatedTypeDecl) -> DocumentSymbol {
    let range = LSPRange(d.site)
    let selectionRange = LSPRange(d.identifier.site)

    return DocumentSymbol(
      name: d.identifier.value,
      detail: nil,
      kind: SymbolKind.struct,
      range: range,
      selectionRange: selectionRange
    )
  }

  func getSymbol(_ d: TypeAliasDecl) -> DocumentSymbol {
    let range = LSPRange(d.site)
    let selectionRange = LSPRange(d.identifier.site)

    return DocumentSymbol(
      name: d.identifier.value,
      detail: nil,
      kind: SymbolKind.struct,
      range: range,
      selectionRange: selectionRange
    )
  }


  func getSymbol(_ d: ConformanceDecl) -> DocumentSymbol {
    let range = LSPRange(d.site)
    let sub = ast[d.subject]
    let type = program.exprType[d.subject]
    let selectionRange = LSPRange(sub.site)

    let name = if let type = type { name(of: type ) } else { "conformance" }

    return DocumentSymbol(
      name: name,
      detail: nil,
      kind: SymbolKind.struct,
      range: range,
      selectionRange: selectionRange,
      children: getSymbols(d.members)
    )
  }

  func getSymbol(_ d: TraitDecl) -> DocumentSymbol {
    let range = LSPRange(d.site)
    let selectionRange = LSPRange(d.identifier.site)

    return DocumentSymbol(
      name: d.identifier.value,
      detail: nil,
      kind: SymbolKind.interface,
      range: range,
      selectionRange: selectionRange,
      children: getSymbols(d.members)
    )
  }

  func getSymbol(_ d: FunctionDecl) -> DocumentSymbol {
    let range = LSPRange(d.site)
    let selectionRange = LSPRange(d.identifier?.site ?? d.site)

    return DocumentSymbol(
      name: d.identifier?.value ?? "fun",
      detail: nil,
      kind: SymbolKind.function,
      range: range,
      selectionRange: selectionRange
    )
  }

  func getSymbols(_ d: MethodDecl) -> [DocumentSymbol] {
    let range = LSPRange(d.site)
    let selectionRange = LSPRange(d.identifier.site)

    return [DocumentSymbol(
      name: d.identifier.value,
      detail: nil,
      kind: SymbolKind.method,
      range: range,
      selectionRange: selectionRange
    )]

    // return d.impls.map { i in
    //   let i = ast[i]
    //   let range = LSPRange(i.site)
    //   let selectionRange = LSPRange(i.introducer.site)

    //   return DocumentSymbol(
    //     name: d.identifier.value,
    //     detail: nil,
    //     kind: SymbolKind.method,
    //     range: range,
    //     selectionRange: selectionRange
    //   )

  }


  func getSymbol(_ d: InitializerDecl) -> DocumentSymbol {
    let range = LSPRange(d.site)
    let selectionRange = LSPRange(d.introducer.site)

    return DocumentSymbol(
      name: "init",
      detail: nil,
      kind: SymbolKind.constructor,
      range: range,
      selectionRange: selectionRange
    )
  }

  func getSymbol(_ d: SubscriptDecl) -> DocumentSymbol {
    let range = LSPRange(d.site)
    let selectionRange = LSPRange(d.introducer.site)
    let name = d.identifier?.value ?? "subscript"

    return DocumentSymbol(
      name: name,
      detail: nil,
      kind: SymbolKind.constructor,
      range: range,
      selectionRange: selectionRange
    )
  }

  func getSymbols(_ d: BindingDecl) -> [DocumentSymbol] {
    let p = ast[d.pattern]
    var symbols: [DocumentSymbol] = []
    getSymbols(p.subpattern, program: program, ast: ast, symbols: &symbols)
    return symbols
  }

  func getSymbols(_ pattern: AnyPatternID, program: TypedProgram, ast: AST, symbols: inout [DocumentSymbol]) {
    let p = ast[pattern]

    switch p {
    case let p as NamePattern:
      let v = ast[p.decl]
        let detail: String? = if let type = program.declType[p.decl] {
          type.description
        }
        else {
          nil
        }

      symbols.append(DocumentSymbol(
        name: v.identifier.value,
        detail: detail,
        kind: SymbolKind.field,
        range: LSPRange(v.site),
        selectionRange: LSPRange(v.identifier.site)
      ))

    case let p as BindingPattern:
      getSymbols(p.subpattern, program: program, ast: ast, symbols: &symbols)
    case let p as TuplePattern:
      for e in p.elements {
        getSymbols(e.pattern, program: program, ast: ast, symbols: &symbols)
      }
    default:
      logger.debug("Unknown pattern: \(p)")
    }
  }

  func kind(_ id: AnyDeclID) -> SymbolKind {
    switch id.kind {
      case BindingDecl.self: return SymbolKind.field
      case VarDecl.self: return SymbolKind.field
      case InitializerDecl.self: return SymbolKind.constructor
      case FunctionDecl.self: return SymbolKind.function
      case SubscriptDecl.self: return SymbolKind.function
      case ProductTypeDecl.self: return SymbolKind.struct
      case ConformanceDecl.self: return SymbolKind.struct
      case TraitDecl.self: return SymbolKind.interface
      default: return SymbolKind.object
    }
  }

  func name(of t: AnyType) -> String {
    switch t.base {
    case let u as ProductType:
      return u.name.value
    case let u as TypeAliasType:
      return u.name.value
    // case let u as ConformanceLensType:
    //   return u.name.value
    case let u as AssociatedTypeType:
      return u.name.value
    case let u as GenericTypeParameterType:
      return u.name.value
    case let u as NamespaceType:
      return u.name.value
    case let u as TraitType:
      return u.name.value
    default:
      // logger.warning("Unexpected type: \(t.base)")
      return "unknown"
    }
  }

}

extension AST {
  public func listDocumentSymbols(_ document: AnalyzedDocument) -> [DocumentSymbol] {
    logger.debug("List symbols in document: \(document.uri)")
    guard let translationUnit = findTranslationUnit(document.uri) else {
      logger.error("Failed to locate translation unit: \(document.uri)")
      return []
    }
    var walker = DocumentSymbolWalker(document: document, translationUnit: self[translationUnit])
    return walker.walk()
  }
}
