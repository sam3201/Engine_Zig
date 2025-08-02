#!/bin/bash

echo "Building WASM version..."
zig build-exe src/wasm_main.zig -target wasm32-freestanding -O ReleaseSmall --name main --export=wasm_init --export=wasm_update --export=wasm_handle_input --export=wasm_get_last_key --export=wasm_alloc -fno-entry

if [ $? -eq 0 ]; then
    echo "Build successful, moving to docs folder..."
    mv main.wasm docs/
    rm main.wasm.o
else
    exit 1
fi
