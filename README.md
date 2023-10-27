# Hylo LSP

Proof of concept LSP server for the [Hylo](https://github.com/hylo-lang/hylo) programming language, including VS Code extension.

The [Hylo VSCode extension](https://github.com/koliyo/hylo-vscode-extension) dynamically downloads the LSP binaries for the current machine OS/architecture.

This is currently very early in development!

## Features

The Hylo LSP currently support the following LSP features:

- Semantic token
  - Syntax highlighting
- Document symbols
  - Document outline and navigate to local symbol
- Definition
  - Jump to definition
- Diagnostics
  - Errors and warnings reported by the compiler

The LSP distribution currently includes a copy of the Hylo stdlib, until we have a reliable way of locating the local Hylo installation.

## Developer

To build and install a local dev version of the LSP + VSCode extension:

```sh
./build-and-install-vscode-extension.sh
```

### Command line tool

There is also a command line tool for interacting with the LSP backend. The command line tool is useful for debugging and testing new functionality. The LSP server is embedded in the client, which simplify debug launching and breakpoints.

Example usage:

```sh
swift run hylo-lsp-client semantic-token hylo/Examples/factorial.hylo
```
