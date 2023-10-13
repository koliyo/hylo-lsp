import XCTest
import JSONRPC
import LanguageServerProtocol
import LanguageServerProtocol_Server
import Logging
import Puppy

@testable import hylo_lsp

func XCTUnwrapAsync<T>(_ expression: @autoclosure () async throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async throws -> T {
  let val = try await expression()
  return try XCTUnwrap(val, message(), file: file, line: line)
}


final class val_lspTests: XCTestCase {

    func testFindDocumentRelativeWorkspacePath() async throws {
        logger = Logger(label: loggerLabel) { label in
          StreamLogHandler.standardOutput(label: label)
        }

        logger.logLevel = .debug

        let dataChannel = DataChannel.stdioPipe()
        let lsp = JSONRPCServer(dataChannel)
        let state = ServerState(lsp: lsp)

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

        _ = await state.initialize(initParam)

        var ws1 = await state.getWorkspaceFile("/foo/a/x.hylo")
        var ws = try XCTUnwrap(ws1)
        XCTAssert(ws.relativePath == "x.hylo")
        XCTAssert(ws.workspace == "/foo/a")

        ws1 = await state.getWorkspaceFile("/foo/b/x.hylo")
        ws = try XCTUnwrap(ws1)
        XCTAssert(ws.relativePath == "x.hylo")
        XCTAssert(ws.workspace == "/foo/b")

        ws1 = await state.getWorkspaceFile("/foo/b/c/x.hylo")
        ws = try XCTUnwrap(ws1)
        XCTAssert(ws.relativePath == "x.hylo")
        XCTAssert(ws.workspace == "/foo/b/c")
    }
}
