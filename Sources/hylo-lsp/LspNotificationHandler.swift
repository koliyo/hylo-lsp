import JSONRPC
import LanguageServerProtocol

public protocol NotificationHandler {
  func initialized(_ params: InitializedParams) async
  func exit() async
  func textDocumentDidOpen(_ params: DidOpenTextDocumentParams) async
  func textDocumentDidChange(_ params: DidChangeTextDocumentParams) async
  func textDocumentDidClose(_ params: DidCloseTextDocumentParams) async
  func textDocumentWillSave(_ params: WillSaveTextDocumentParams) async
  func textDocumentDidSave(_ params: DidSaveTextDocumentParams) async
  func protocolCancelRequest(_ params: CancelParams) async
  func protocolSetTrace(_ params: SetTraceParams) async
  func workspaceDidChangeWatchedFiles(_ params: DidChangeWatchedFilesParams) async
  func windowWorkDoneProgressCancel(_ params: WorkDoneProgressCancelParams) async
  func workspaceDidChangeWorkspaceFolders(_ params: DidChangeWorkspaceFoldersParams) async
  func workspaceDidChangeConfiguration(_ params: DidChangeConfigurationParams) async
  func workspaceDidCreateFiles(_ params: CreateFilesParams) async
  func workspaceDidRenameFiles(_ params: RenameFilesParams) async
  func workspaceDidDeleteFiles(_ params: DeleteFilesParams) async
}

public extension NotificationHandler {
  func handleNotification(_ notification: ClientNotification) async {
    print("notification: \(notification.method)")

    switch notification {
    case let .initialized(params):
      await initialized(params)
    case .exit:
      await exit()
    case let .textDocumentDidOpen(params):
      await textDocumentDidOpen(params)
    case let .textDocumentDidChange(params):
      await textDocumentDidChange(params)
    case let .textDocumentDidClose(params):
      await textDocumentDidClose(params)
    case let .textDocumentWillSave(params):
      await textDocumentWillSave(params)
    case let .textDocumentDidSave(params):
      await textDocumentDidSave(params)
    case let .protocolCancelRequest(params):
      await protocolCancelRequest(params)
    case let .protocolSetTrace(params):
      await protocolSetTrace(params)
    case let .workspaceDidChangeWatchedFiles(params):
      await workspaceDidChangeWatchedFiles(params)
    case let .windowWorkDoneProgressCancel(params):
      await windowWorkDoneProgressCancel(params)
    case let .workspaceDidChangeWorkspaceFolders(params):
      await workspaceDidChangeWorkspaceFolders(params)
    case let .workspaceDidChangeConfiguration(params):
      await workspaceDidChangeConfiguration(params)
    case let .workspaceDidCreateFiles(params):
      await workspaceDidCreateFiles(params)
    case let .workspaceDidRenameFiles(params):
      await workspaceDidRenameFiles(params)
    case let .workspaceDidDeleteFiles(params):
      await workspaceDidDeleteFiles(params)
    }
  }
}
