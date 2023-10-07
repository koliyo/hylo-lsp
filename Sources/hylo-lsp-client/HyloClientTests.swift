import Foundation
import LanguageClient
// import ProcessEnv
import LanguageClient
import LanguageServerProtocol
import LanguageServerProtocol_Client
import JSONRPC

import Core
import FrontEnd
import IR
import hylo_lsp

public func createServer(channel: DataChannel, workspace: URL, documents: [URL]) async throws -> RestartingServer<JSONRPCServer> {
  let jsonServer = JSONRPCServer(dataChannel: channel)
  // let workspaceDirectory = docURL.deletingLastPathComponent()

  let initializationProvider: InitializingServer.InitializeParamsProvider = {
      // you may need to fill in more of the textDocument field for completions
      // to work, depending on your server
      let capabilities = ClientCapabilities(workspace: nil,
                                            textDocument: nil,
                                            window: nil,
                                            general: nil,
                                            experimental: nil)

      // pay careful attention to rootPath/rootURI/workspaceFolders, as different servers will
      // have different expectations/requirements here
      let ws = WorkspaceFolder(uri: workspace.absoluteString, name: "workspace")

      return InitializeParams(processId: Int(ProcessInfo.processInfo.processIdentifier),
                              locale: nil,
                              rootPath: nil,
                              rootUri: nil,
                              // rootUri: projectURL.absoluteString,
                              initializationOptions: nil,
                              capabilities: capabilities,
                              trace: nil,
                              workspaceFolders: [ws])
  }


  let docs = try documents.map { url in
    let docContent = try String(contentsOf: url)
    return TextDocumentItem(
      uri: url.absoluteString,
      // uri: url.path,
      languageId: .swift,
      version: 1,
      text: docContent)
  }.reduce(into: [DocumentUri:TextDocumentItem]()) { (dict, item) in
    dict[item.uri] = item
  }

  let documentProvider = { @Sendable (uri: DocumentUri) in

    guard let doc = docs[uri] else {
      throw RestartingServerError.noTextDocumentForURI(uri)
    }

    return doc
  }


  // let server = InitializingServer(server: jsonServer, initializeParamsProvider: provider)
  let rsConf = RestartingServer.Configuration(
    serverProvider: { jsonServer },
    textDocumentItemProvider: documentProvider,
    initializeParamsProvider: initializationProvider
  )

  let server = RestartingServer(configuration: rsConf)

  for doc in docs.values {
    print("Open: \(doc.uri)")
    let docParams = TextDocumentDidOpenParams(textDocument: doc)
    try await server.textDocumentDidOpen(params: docParams)
  }

  return server
}


// func RunHyloClientTests(channel: DataChannel, docURL: URL) async {
//   do {
//     let server = try await createServer(channel: channel, docURL: docURL)
//     if let c = await server.capabilities {
//       if let semanticTokensProvider = c.semanticTokensProvider {
//         print("Server legend: \(semanticTokensProvider.effectiveOptions.legend)")
//       }
//     }

//     // make sure to pick a reasonable position within your test document
//     // NOTE: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#position
//     // Position in a text document expressed as zero-based line and zero-based character offset. A position is between two characters like an ‘insert’ cursor in an editor. Special values like for example -1 to denote the end of a line are not supported.
//     // let completionParams = CompletionParams(uri: docURL.absoluteString,
//     //                                         position: pos,
//     //                                         triggerKind: .invoked,
//     //                                         triggerCharacter: nil)
//     // let completions = try await server.completion(params: completionParams)
//     // print("completions: ", completions!)

//     do {
//       print("get symbols")
//       let params = DocumentSymbolParams(textDocument: TextDocumentIdentifier(uri: docURL.absoluteString))
//       if let symbols = try await server.documentSymbol(params: params) {
//         if case let .optionA(symbols) = symbols {
//           print("symbols: ", symbols.map { $0.name })
//         }
//       }
//     }

//     do {
//       print("get semantic tokens")
//       let params = SemanticTokensParams(textDocument: TextDocumentIdentifier(uri: docURL.absoluteString))
//       if let tokens = try await server.semanticTokensFull(params: params) {
//         var currentLine: UInt32 = 0
//         var currentCol: UInt32 = 0
//         let d = tokens.data
//         for n in 0..<d.count/5 {
//           let i = n * 5
//           let line = d[i] + currentLine
//           let col = d[i+1] + currentCol
//           let len = d[i+2]
//           let type = TokenType(rawValue: d[i+3])!
//           let modifiers = d[i+4]

//           if d[i] > 0 {
//             currentLine += d[i]
//             currentCol += 1
//           }
//           print("line: \(line), col: \(col), len: \(len), type: \(type), modifiers: \(modifiers)")
//         }
//       }
//     }

//     do {
//       // let pos = Position(line: 10, character: 14)
//       // let pos = Position(line: 10, character: 26)
//       // let pos = Position(line: 10, character: 35)
//       // let pos = Position(line: 3, character: 10)
//       // let pos = Position(line: 3, character: 29)
//       // let pos = Position(line: 20, character: 32)
//       // let pos = Position(line: 18, character: 37)
//       let pos = Position(line: 20, character: 8)
//       let params = TextDocumentPositionParams(uri: docURL.absoluteString, position: pos)
//       if let definition = try await server.definition(params: params) {
//         print("definition: ", definition)
//       }
//     }


//     print("exit")
//     // try client.close()
//     // try socket.close()

//   } catch UniSocketError.error(let detail) {
//     print("fail: \(detail)")
//   } catch let e as AnyJSONRPCResponseError {
//     print("rpc error: [\(e.code)] \(e.message)")
//   } catch {
//     print("error: \(error), type: \(type(of: error))")
//     print(Thread.callStackSymbols)
//   }
// }
