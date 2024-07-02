#!/bin/bash

set -ex

swift build -c release
BUILD_DIR=$(swift build -c release --show-bin-path)
DIST_DIR=hylo-vscode-extension/dist
rm -rf $DIST_DIR
mkdir -p $DIST_DIR
cp -Rp hylo/StandardLibrary/Sources $DIST_DIR/hylo-stdlib
mkdir -p $DIST_DIR/bin/
cp -fv $BUILD_DIR/hylo-lsp-server $DIST_DIR/bin/
PUBLISHED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "{\"name\": \"dev\", \"id\": 0, \"published_at\": \"$PUBLISHED_AT\"}" > $DIST_DIR/manifest.json
cd hylo-vscode-extension
npm install
npm run vscode:package
VERSION=$(cat package.json | jq -r ".version")
code --install-extension hylo-lang-$VERSION.vsix
