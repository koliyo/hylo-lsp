import Foundation
//import LanguageClient
import ProcessEnv
import LanguageServerProtocol
import JSONRPC
import UniSocket
import JSONRPC_DataChannel_UniSocket
import JSONRPC_DataChannel_StdioPipe
import ArgumentParser
import hylo_lsp

extension Bool {
    var intValue: Int {
        return self ? 1 : 0
    }
}

@main
struct HyloLspCommand: AsyncParsableCommand {

    @Flag(help: "Stdio transport")
    var stdio: Bool = false

    @Option(help: "Named pipe transport")
    var pipe: String?

    @Option(help: "Socket transport")
    var socket: String?

    func validate() throws {
      // let numTransports = stdio.intValue + (pipe != nil).intValue + (socket != nil).intValue
      // guard numTransports == 1 else {
      //     throw ValidationError("Exactly one transport method must be defined")
      // }
    }


    func run() async throws {
        print("args: \(CommandLine.arguments)")
        fflush(stdout)

        if stdio {
          let channel = DataChannel.stdioPipe()
          let server = HyloServer(channel)
          await server.run()
        }
        else if let socket = socket {
          // throw ValidationError("TODO: socket transport: \(socket)")
          let socket = try UniSocket(type: .tcp, peer: socket, timeout: (connect: 5, read: nil, write: 5))
          try socket.attach()
          let channel = DataChannel(socket: socket)
          let server = HyloServer(channel)
          await server.run()
        }
        else if let pipe = pipe {
          let socket = try UniSocket(type: .local, peer: pipe, timeout: (connect: 5, read: nil, write: 5))
          try socket.attach()
          let channel = DataChannel(socket: socket)
          let server = HyloServer(channel)
          await server.run()
        }
    }
}


// print("SERVER with args: \(CommandLine.arguments)")
// await HyloLspCommand.main2()

// // let x = ProcessInfo.processInfo.userEnvironment
// let x = ProcessInfo.processInfo.environment
// // let params = Process.ExecutionParameters(path: "/path/to/server-executable",
// //                                          arguments: [],
// //                                         //  environment: [:])
// //                                          environment: ProcessInfo.processInfo.userEnvironment)

// // let channel = DataChannel.localProcessChannel(parameters: params, terminationHandler: { print("terminated") })

// // print("hello2: \(x)")

// // let x = JSONRPCServer(dataChannel: channel)
// do {
// 	let socket = try UniSocket(type: .local, peer: "/tmp/my_socket", timeout: (connect: 5, read: nil, write: 5))
// 	try socket.attach()

//   let channel = DataChannel(socket: socket)
//   let server = LspServer(dataChannel: channel)
//   // let server = JSONRPCServer(dataChannel: channel)
//   let noteSequence = server.notificationSequence
//   let requestSequence = server.requestSequence
//   // let session = JSONRPCSession(channel: channel)
//   // let noteSequence = await session.notificationSequence
//   // let requestSequence = await session.requestSequence

//   let t1 = Task {
//     print("t1")
//     for await notification in noteSequence {
//       print("notification: \(notification)")
//     }
//     // for await (notification, data) in noteSequence {
//     //   print("notification: \(notification), data: \(data)")
//     // }

//   }

//   // await t1.result

//   let t2 = Task {
//     print("t2")
//     for await (request) in requestSequence {
//       print("request: \(request)")
//     }

//     // for await (request, handler, data) in requestSequence {
//     //   print("request: \(request), data: \(data), handler: \(handler)")
//     // }
//   }

//   let _ = await [t1.result, t2.result]

//   // let d = "foo".data(using: .utf8)!
//   // try socket.send(d)
// 	// print("sent!")
// 	// let data = try socket.recv()
//   // let str = String(decoding: data, as: UTF8.self)
// 	// print("server responded with: \(str)")
//   print("exit")
// 	try socket.close()

// } catch UniSocketError.error(let detail) {
// 	print("fail: \(detail)")
// }


