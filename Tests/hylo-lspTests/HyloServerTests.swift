import XCTest
import JSONRPC
import LanguageServerProtocol
import LSPServer
import Logging
import Puppy

@testable import hylo_lsp

func XCTUnwrapAsync<T>(_ expression: @autoclosure () async throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async throws -> T {
  let val = try await expression()
  return try XCTUnwrap(val, message(), file: file, line: line)
}


final class hyloLspTests: XCTestCase {
  func createLogger() -> Logger {
    var logger = Logger(label: loggerLabel) { label in
      StreamLogHandler.standardOutput(label: label)
    }

    logger.logLevel = .debug
    return logger
  }

  func testApplyDocumentChanges() async throws {
    let uri = "file:///factorial.hylo"
    let beforeEdit = """
    fun factorial(_ n: Int) -> Int {
      if n < 2 { 1 } else { n * factorial(n - 1) }
    }

    public fun main() {
      let _ = factorial(6)
    }
    """

    let afterEdit = """
    fun foo(_ n: Int) -> Int {
      if n < 2 { 1 } else { n * factorial(n - 1) }
    }
    public fun main() {
      let _ = foo(123)
    }
    """

    let textDocument = TextDocumentItem(uri: uri, languageId: "hylo", version: 0, text: beforeEdit)

    let doc = Document(textDocument: textDocument)

    let changes = [
      TextDocumentContentChangeEvent(range: LSPRange(startPair: (0, 4), endPair: (0, 13)), rangeLength: nil, text: "foo"),
      TextDocumentContentChangeEvent(range: LSPRange(startPair: (3, 0), endPair: (3, 1)), rangeLength: nil, text: ""),
      TextDocumentContentChangeEvent(range: LSPRange(startPair: (4, 10), endPair: (4, 19)), rangeLength: nil, text: "foo"),
      TextDocumentContentChangeEvent(range: LSPRange(startPair: (4, 14), endPair: (4, 15)), rangeLength: nil, text: "123"),
    ]

    let updatedDoc = try doc.withAppliedChanges(changes, nextVersion: 2)
    XCTAssertEqual(updatedDoc.text, afterEdit)
  }

  func testFindDocumentRelativeWorkspacePath() async throws {
    let logger = createLogger()
    let dataChannel = DataChannel.stdioPipe()
    let connection = JSONRPCClientConnection(dataChannel)
    let documentProvider = DocumentProvider(connection: connection, logger: logger)

    let caps = ClientCapabilities(workspace: nil, textDocument: nil, window: nil, general: nil, experimental: nil)

    let initParam = InitializeParams(
      processId: 1,
      locale: nil,
      rootPath: nil,
      rootUri: "/foo/a",
      initializationOptions: nil,
      capabilities: caps,
      trace: nil,
      workspaceFolders: [
        WorkspaceFolder(uri: "/foo/b", name: "b"),
        WorkspaceFolder(uri: "/foo/b/c", name: "b/c"),
      ]
    )

    _ = await documentProvider.initialize(initParam)

    var ws1 = await documentProvider.getWorkspaceFile("/foo/a/x.hylo")
    var ws = try XCTUnwrap(ws1)
    XCTAssert(ws.relativePath == "x.hylo")
    XCTAssert(ws.workspace == "/foo/a")

    ws1 = await documentProvider.getWorkspaceFile("/foo/b/x.hylo")
    ws = try XCTUnwrap(ws1)
    XCTAssert(ws.relativePath == "x.hylo")
    XCTAssert(ws.workspace == "/foo/b")

    ws1 = await documentProvider.getWorkspaceFile("/foo/b/c/x.hylo")
    ws = try XCTUnwrap(ws1)
    XCTAssert(ws.relativePath == "x.hylo")
    XCTAssert(ws.workspace == "/foo/b/c")
  }
}
