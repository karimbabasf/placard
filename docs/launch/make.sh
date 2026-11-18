#!/bin/sh
# Builds docs/launch/placard-launch.mp4 (10 s, 1920x1080, 60 fps): Swift textures, Blender wall, Swift end card, ffmpeg grade.
set -e
cd "$(dirname "$0")"
B=build
swift textures.swift $B/tex
[ -n "$SKIP_3D" ] || { rm -rf $B/3d/frames; blender -b -P scene.py -- $B/tex $B/3d/frames --render > $B/render.log 2>&1; }
swift endcard.swift $B/2d
# 3D 510 frames (8.5 s), end card 108 frames (1.8 s), 0.3 s crossfade: exactly 10.0 s
ffmpeg -loglevel error -y \
  -framerate 60 -start_number 1 -i $B/3d/frames/%04d.png \
  -framerate 60 -start_number 1 -i $B/2d/cap_%04d.png \
  -framerate 60 -start_number 1 -i $B/2d/end_%04d.png \
  -filter_complex "\
[0:v][1:v]overlay=format=auto,format=gbrp,settb=1/60[a];[2:v]format=gbrp,settb=1/60[b];\
[a][b]xfade=transition=fade:duration=0.3:offset=8.2,format=gbrp[v];\
[v]split[x][y];[y]curves=all='0/0 0.6/0 1/1',gblur=sigma=24[g];[x][g]blend=all_mode=screen:all_opacity=0.35,format=gbrp[bl];\
[bl]vignette=angle=PI/6,noise=alls=2:allf=t,format=yuv420p[out]" \
  -map "[out]" -c:v libx264 -preset slow -crf 19 -profile:v high -movflags +faststart -r 60 placard-launch.mp4
ls -lh placard-launch.mp4
