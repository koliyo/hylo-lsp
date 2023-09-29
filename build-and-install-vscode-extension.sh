#!/bin/bash

set -ex

# . ./setup-env.sh
swift build -c release
BUILD_DIR=$(swift build -c release --show-bin-path)
DIST_DIR=hylo-vscode-extension/dist
mkdir -p $DIST_DIR
rm -rf $DIST_DIR/stdlib
cp -Rp hylo/Library/Hylo $DIST_DIR/stdlib
mkdir -p $DIST_DIR/bin/mac/arm64
cp -fv $BUILD_DIR/hylo-lsp-server $DIST_DIR/bin/mac/arm64
cd hylo-vscode-extension
npm install
npm run vscode:package
VERSION=$(cat package.json | jq -r ".version")
code --install-extension hylo-lang-$VERSION.vsix
