#!/bin/bash

set -ex

# . ./setup-env.sh
swift build -c release
BUILD_DIR=$(swift build -c release --show-bin-path)
mkdir -p hylo-vscode-extension/bin/mac/arm64
cp -fv $BUILD_DIR/hylo-lsp-server hylo-vscode-extension/bin/mac/arm64
cd hylo-vscode-extension
npm install
npm run vscode:package
VERSION=$(cat package.json | jq -r ".version")
code --install-extension hylo-lang-$VERSION.vsix
