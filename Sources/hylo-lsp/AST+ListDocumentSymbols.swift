import Core
import FrontEnd
import IR
import LanguageServerProtocol

struct DocumentSymbolWalker {
  public let document: DocumentUri
  public let translationUnit: TranslationUnit
  public let program: TypedProgram
  public let ast: AST
  private(set) var symbols: [AnyDeclID]

  public init(document: DocumentUri, translationUnit: TranslationUnit, program: TypedProgram, ast: AST) {
    self.document = document
    self.translationUnit = translationUnit
    self.program = program
    self.ast = ast
    self.symbols = []
  }


  public mutating func walk() -> [AnyDeclID] {
    precondition(symbols.isEmpty)
    addMembers(translationUnit.decls)
    return symbols
  }

  mutating func addMembers(_ members: [AnyDeclID]) {
    for m in members {
      addDecl(m)
    }
  }


  mutating func addDecl(_ id: AnyDeclID) {
    let node = ast[id]
    logger.debug("Found symbol node: \(id), site: \(node.site)")
    symbols.append(id)
    addMembers(id: id, node: node)
  }

  mutating func addMembers(id: AnyDeclID, node: Node) {

    switch node {
    case let d as NamespaceDecl:
      addMembers(d.members)
    case let d as ProductTypeDecl:
      addMembers(d.members)
    case let d as ExtensionDecl:
      addMembers(d.members)
    case let d as ConformanceDecl:
      addMembers(d.members)
    case let d as TraitDecl:
      addMembers(d.members)
    default:
      // print("Ignored declaration node: \(node)")
      break
    }
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
        // logger.debug("Enter file: \(site.file.url)")
      }
    }

    if n.kind == NamespaceDecl.self || n.kind == TranslationUnit.self {
      return true
    }


    if n.kind == BindingDecl.self {
      return true
    }

    // if n.kind == FunctionDecl.self || n.kind == VarDecl.self {
    if let d = AnyDeclID(n) {
      logger.debug("Found symbol node: \(d), site: \(site)")
      symbols.append(d)
      return false
    }

    // logger.debug("Ignore node: \(n)")
    return true
  }
}

extension AST {
  public func listDocumentSymbols(_ document: DocumentUri, _ program: TypedProgram) -> [AnyDeclID] {
    logger.debug("List symbols in document: \(document)")
    guard let translationUnit = findTranslationUnit(document) else {
      logger.error("Failed to locate translation unit: \(document)")
      return []
    }
    var walker = DocumentSymbolWalker(document: document, translationUnit: self[translationUnit], program: program, ast: self)
    return walker.walk()
  }
}
