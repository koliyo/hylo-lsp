import Foundation
import LanguageClient
// import ProcessEnv
import LanguageServerProtocol
import JSONRPC
import UniSocket
import JSONRPC_DataChannel_UniSocket
import JSONRPC_DataChannel_Actor
import ArgumentParser
import Logging
import hylo_lsp

import Core
import FrontEnd
import IR


// Allow loglevel as `ArgumentParser.Option`
extension Logger.Level : ExpressibleByArgument {
}

let pipePath = "/tmp/my.sock"

@main
struct HyloLspCommand: AsyncParsableCommand {

    @Flag(help: "Named pipe transport")
    var pipe: Bool = false

    @Option(help: "Log level")
    var log: Logger.Level = Logger.Level.debug

    func validate() throws {
    }

    func run() async throws {
      logger.logLevel = log

      if pipe {
        print("starting client witn named pipe: \(pipePath)")
        let fileManager = FileManager.default

        // Check if file exists
        if fileManager.fileExists(atPath: pipePath) {
            // Delete file
            print("delete existing socket: \(pipePath)")
            try fileManager.removeItem(atPath: pipePath)
        }

        let socket = try UniSocket(type: .local, peer: pipePath)
        try socket.bind()
        try socket.listen()
        let client = try socket.accept()
        print("lsp attached")
        client.timeout = (connect: 5, read: nil, write: 5)
        let clientChannel = DataChannel(socket: client)
        await RunHyloClientTests(clientChannel)
      }
      else {
        let (clientChannel, serverChannel) = DataChannel.withDataActor()

        Task {
          let server = HyloServer(serverChannel, logger: logger)
          await server.run()
        }

        await RunHyloClientTests(clientChannel)
      }
    }
}


