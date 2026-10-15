#!/usr/bin/env bash
# Regenerates the README animation, starfield.png: animated PNG, 60 fps, seamless loop.
# macOS only; needs swiftc and ffmpeg.
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
swiftc -O render-frames.swift -o "$tmp/render"

"$tmp/render" 60 "$tmp/f60" >/dev/null
ffmpeg -y -loglevel error -framerate 60 -i "$tmp/f60/f%04d.png" \
  -vf "scale=800:450:flags=lanczos,format=gray" -plays 0 -f apng starfield.png

rm -rf "$tmp"
