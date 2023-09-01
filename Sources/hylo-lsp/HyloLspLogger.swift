import Logging

// NOTE: Currently using a global logger
public let loggerLabel = "hylo-lsp"
public var logger : Logger = Logger(label: loggerLabel)

// https://github.com/apple/swift-log/issues/63
internal extension Logger {
  func debug(_ message: String) {
    debug(Logger.Message(stringLiteral: message))
  }

  func info(_ message: String) {
    info(Logger.Message(stringLiteral: message))
  }

  func warning(_ message: String) {
    warning(Logger.Message(stringLiteral: message))
  }

  func error(_ message: String) {
    error(Logger.Message(stringLiteral: message))
  }
}
