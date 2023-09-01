import Foundation
import JSONRPC
import LanguageServerProtocol


public protocol ProtocolHandler {
  var lsp: LspServer { get }
}

public extension ProtocolHandler {

  func logInternalError(_ message: String, type: MessageType = .warning) async {
    do {
      try await lsp.sendNotification(.windowLogMessage(LogMessageParams(type: type, message: message)))
    }
    catch {
      print(message)
    }
  }

}
