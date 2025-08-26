!/usr/bin/env bash
set -e
zig build -Dstatic-llvm=false
./zig-out/bin/Engine
