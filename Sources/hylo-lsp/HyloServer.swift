import JSONRPC
import LanguageServerProtocol
import LanguageServer
import Foundation
import Semaphore

@preconcurrency import Core
import FrontEnd
import Logging

public struct HyloErrorHandler : ErrorHandler {
  let logger: Logger

	public func internalError(_ error: Error) async {
    logger.debug("LSP stream error: \(error)")
  }
}


public actor HyloServer {
  let connection: JSONRPCClientConnection
  private let logger: Logger
  private var documentProvider: DocumentProvider
  private let dispatcher: EventDispatcher
  var exitSemaphore: AsyncSemaphore

  public static let disableLogging = if let disableLogging = ProcessInfo.processInfo.environment["HYLO_LSP_DISABLE_LOGGING"] { !disableLogging.isEmpty } else { false }

  public init(_ dataChannel: DataChannel, logger: Logger) {
    self.logger = logger
    connection = JSONRPCClientConnection(dataChannel)
    self.documentProvider = DocumentProvider(connection: connection, logger: logger)
    let requestHandler = HyloRequestHandler(connection: connection, logger: logger, documentProvider: documentProvider)

    exitSemaphore = AsyncSemaphore(value: 0)

    let notificationHandler = HyloNotificationHandler(connection: connection, logger: logger, documentProvider: documentProvider, exitSemaphore: exitSemaphore)
    let errorHandler = HyloErrorHandler(logger: logger)

    dispatcher = EventDispatcher(connection: connection, requestHandler: requestHandler, notificationHandler: notificationHandler, errorHandler: errorHandler)
  }

  public func run() async {
    logger.debug("starting server")
    await dispatcher.run()
    logger.debug("dispatcher completed")
    await exitSemaphore.wait()
    logger.debug("exit")
  }
}
