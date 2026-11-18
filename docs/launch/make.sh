#!/bin/sh
# Builds docs/launch/placard-launch.mp4 (5 s, 1920x1080, 60 fps): Swift textures, Blender wall, Swift end card, ffmpeg grade.
set -e
cd "$(dirname "$0")"
B=build
swift textures.swift $B/tex
[ -n "$SKIP_3D" ] || { rm -rf $B/3d/frames; blender -b -P scene.py -- $B/tex $B/3d/frames --render > $B/render.log 2>&1; }
swift endcard.swift $B/2d
ffmpeg -loglevel error -y \
  -framerate 60 -start_number 1 -i $B/3d/frames/%04d.png \
  -framerate 60 -start_number 1 -i $B/2d/cap_%04d.png \
  -framerate 60 -start_number 1 -i $B/2d/end_%04d.png \
  -filter_complex "\
[0:v][1:v]overlay=format=auto,format=rgb24[a];[2:v]format=rgb24[b];[a][b]concat=n=2:v=1[v];\
[v]split[x][y];[y]curves=all='0/0 0.55/0 1/1',gblur=sigma=26[g];[x][g]blend=all_mode=screen:all_opacity=0.55[bl];\
[bl]vignette=angle=PI/5,noise=alls=5:allf=t,format=yuv420p[out]" \
  -map "[out]" -c:v libx264 -preset slow -crf 15 -profile:v high -movflags +faststart -r 60 placard-launch.mp4
ls -lh placard-launch.mp4
