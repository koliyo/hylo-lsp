import JSONRPC
import LanguageServer
import Foundation
import Semaphore

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

  public static let disableLogging = if let disableLogging = ProcessInfo.processInfo.environment["HYLO_LSP_DISABLE_LOGGING"] { !disableLogging.isEmpty } else { false }

  public init(_ dataChannel: DataChannel, logger: Logger) {
    self.logger = logger
    self.connection = JSONRPCClientConnection(dataChannel)
  }

  nonisolated private func createDispatcher(exitSemaphore: AsyncSemaphore) -> EventDispatcher {
    let documentProvider = DocumentProvider(connection: connection, logger: logger)
    let requestHandler = HyloRequestHandler(connection: connection, logger: logger, documentProvider: documentProvider)
    let notificationHandler = HyloNotificationHandler(connection: connection, logger: logger, documentProvider: documentProvider, exitSemaphore: exitSemaphore)
    let errorHandler = HyloErrorHandler(logger: logger)

    return EventDispatcher(connection: connection, requestHandler: requestHandler, notificationHandler: notificationHandler, errorHandler: errorHandler)
  }

  public func run() async {
    logger.debug("starting server")
    let exitSemaphore = AsyncSemaphore(value: 0)
    let dispatcher = createDispatcher(exitSemaphore: exitSemaphore)
    await dispatcher.run()
    logger.debug("dispatcher completed")
    await exitSemaphore.wait()
    logger.debug("exit")
  }
}
