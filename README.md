# Val LSP


https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#implementationConsiderations

```md
stdio: uses stdio as the communication channel.
pipe: use pipes (Windows) or socket files (Linux, Mac) as the communication channel. The pipe / socket file name is passed as the next arg or with --pipe=.
socket: uses a socket as the communication channel. The port is passed as next arg or with --port=.
node-ipc: use node IPC communication between the client and the server. This is only supported if both client and server run under node.
```

See: /Users/nils/Work/bravo/lsp/lsp-server/LspTransportExtension.cs


Update packages:

```sh
swift package update
```
