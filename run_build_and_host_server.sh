#!/bin/bash

echo "Building WASM version..."

rm -f wasm_main.o wasm_main.wasm main.o main.wasm libmain.a libmain.a.o wasm_main.o.o

zig build-obj src/wasm_main.zig -target wasm32-freestanding -O ReleaseSmall

if [ $? -eq 0 ]; then
    echo "Build successful, creating WASM file..."
    
    echo "Files created:"
    ls -la wasm_main.* main.* libmain.* 2>/dev/null || echo "No output files found"
    
    if [ -f "wasm_main.o" ]; then
        echo "Found wasm_main.o, renaming to main.wasm"
        mv wasm_main.o docs/main.wasm
    elif [ -f "main.o" ]; then
        echo "Found main.o, renaming to main.wasm"
        mv main.o docs/main.wasm
    elif [ -f "wasm_main.o.o" ]; then
        echo "Found wasm_main.o.o, renaming to main.wasm"
        mv wasm_main.o.o docs/main.wasm
    elif [ -f "libmain.a.o" ]; then
        echo "Found libmain.a.o, renaming to main.wasm"
        mv libmain.a.o docs/main.wasm
    elif [ -f "libmain.a" ]; then
        echo "Found libmain.a, renaming to main.wasm"
        mv libmain.a docs/main.wasm
    else
        echo "No output file found!"
        exit 1
    fi
    
    echo "WASM build complete! File is at docs/main.wasm"
    echo ""
    echo "Starting host server..."
    cd docs
    python3 -m http.server 42069
else
    echo "Build failed!"
    exit 1
fi
