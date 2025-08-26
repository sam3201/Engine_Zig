!/usr/bin/env bash
set -e
zig build
./zig-out/bin/Engine
