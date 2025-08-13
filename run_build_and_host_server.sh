#!/bin/bash
set -e
zig build -Dstatic-llvm=false
./zig-out/bin/Engine
