#!/bin/sh
# Regenerates docs/hero.gif from docs/hero.swift.
set -e
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swift docs/hero.swift "$TMP"
ffmpeg -loglevel error -y -framerate 15 -i "$TMP/f%03d.png" -vf "palettegen=max_colors=192:stats_mode=full" "$TMP/pal.png"
ffmpeg -loglevel error -y -framerate 15 -i "$TMP/f%03d.png" -i "$TMP/pal.png" -lavfi "[0:v][1:v]paletteuse=dither=none:diff_mode=rectangle" -loop 0 docs/hero.gif
cp "$TMP/f040.png" docs/hero-still.png
rm -rf "$TMP"
ls -lh docs/hero.gif
