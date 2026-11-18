#!/usr/bin/env bash
# Builds the saver and checks that leaked (never deallocated) views don't pin GPU memory.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d build/Starfield.saver ] || ./build.sh
mkdir -p build
swiftc -O tests/leak-check.swift -o build/leak-check
build/leak-check build/Starfield.saver
