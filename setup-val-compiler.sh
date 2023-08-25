#!/bin/bash

set -ex

if [[ "$ZSH_VERSION" ]]; then
  BASE_DIR=$( dirname $0:A )
else
  BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
fi

VAL_DIR=$BASE_DIR/val


cd $VAL_DIR
swift package resolve
.build/checkouts/Swifty-LLVM/Tools/make-pkgconfig.sh llvm.pc

export PKG_CONFIG_PATH=$PWD
