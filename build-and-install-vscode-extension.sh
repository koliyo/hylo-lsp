#!/bin/bash

set -ex

# . ./setup-env.sh
swift build -c release
BUILD_DIR=$(swift build -c release --show-bin-path)
DIST_DIR=hylo-vscode-extension/dist
mkdir -p $DIST_DIR
rm -rf $DIST_DIR/hylo-stdlib
cp -Rp hylo/Library/Hylo $DIST_DIR/hylo-stdlib
mkdir -p $DIST_DIR/bin/
cp -fv $BUILD_DIR/hylo-lsp-server $DIST_DIR/bin/
PUBLISHED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "{\"name\": \"dev\", \"id\": 0, \"published_at\": \"$PUBLISHED_AT\"}" > $DIST_DIR/manifest.json
cd hylo-vscode-extension
npm install
npm run vscode:package
VERSION=$(cat package.json | jq -r ".version")
code --install-extension hylo-lang-$VERSION.vsix
