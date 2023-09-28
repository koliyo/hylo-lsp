#!/bin/bash

set -ex

# . ./setup-env.sh
swift build -c release
BUILD_DIR=$(swift build -c release --show-bin-path)
mkdir -p hylo-lsp-vs-code/bin/mac/arm64
cp -fv $BUILD_DIR/hylo-lsp-server hylo-lsp-vs-code/bin/mac/arm64
cd hylo-lsp-vs-code
npm install
npm run vscode:all
code --install-extension hyloc-lsp-0.5.0.vsix
