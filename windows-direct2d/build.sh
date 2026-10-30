#!/usr/bin/env bash
# Cross-compiles dist/Starfield.scr from macOS/Linux with MinGW-w64 (brew install mingw-w64).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist
x86_64-w64-mingw32-g++ -O2 -Wall -Wextra -municode -mwindows -static \
  -o dist/Starfield.scr starfield.cpp \
  -ld2d1 -ld3d11 -ldxgi -luuid -lgdi32 -luser32 -ladvapi32 -lcomctl32 -lshell32
echo "Built dist/Starfield.scr"
