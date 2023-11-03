import Foundation
import LanguageClient
// import ProcessEnv
import LanguageClient
import LanguageServerProtocol
import LSPClient
import JSONRPC

import Core
import FrontEnd
import hylo_lsp

public func textDocument(_ url: URL) throws -> TextDocumentItem {
  let docContent = try String(contentsOf: url)
  return TextDocumentItem(
    uri: url.absoluteString,
    // uri: url.path,
    languageId: .swift,
    version: 1,
    text: docContent)
}

public func createServer(channel: DataChannel, workspace: URL, documents: [URL], openDocuments: Bool = false) async throws -> RestartingServer<JSONRPCServerConnection> {
  let jsonServer = JSONRPCServerConnection(dataChannel: channel)
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


  let docs = try documents.map { try textDocument($0)
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

  if openDocuments {
    for doc in docs.values {
      let docParams = DidOpenTextDocumentParams(textDocument: doc)
      try await server.textDocumentDidOpen(params: docParams)
    }
  }

  return server
}

