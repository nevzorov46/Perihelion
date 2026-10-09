#!/bin/sh
# Command-line tools that compile the app's physics sources directly.
#   tools/run.sh bake     regenerate Perihelion/Game/Levels.swift
#   tools/run.sh verify   check the integrator, the math and every level's proof shot
#   tools/run.sh feel     measure the pull the player feels, to set haptic thresholds
#   tools/run.sh icon [level]   draw the app icon from a real trajectory
set -e
cd "$(dirname "$0")/.."
OUT=.build/tools
mkdir -p "$OUT"
PHYSICS="Perihelion/Physics/*.swift"

case "$1" in
  bake)
    swiftc -O $PHYSICS tools/bake/*.swift -o "$OUT/bake"
    "$OUT/bake" > "$OUT/Levels.swift"
    mv "$OUT/Levels.swift" Perihelion/Game/Levels.swift
    head -14 Perihelion/Game/Levels.swift
    ;;
  verify)
    swiftc -O $PHYSICS Perihelion/Game/Levels.swift tools/verify/*.swift -o "$OUT/verify"
    "$OUT/verify"
    ;;
  feel)
    swiftc -O $PHYSICS Perihelion/Game/Levels.swift tools/feel/*.swift -o "$OUT/feel"
    "$OUT/feel"
    ;;
  icon)
    swiftc -O $PHYSICS Perihelion/Game/Levels.swift tools/icon/*.swift -o "$OUT/icon"
    shift
    "$OUT/icon" "$@"
    ;;
  *)
    echo "usage: tools/run.sh bake|verify|feel|icon" >&2
    exit 1
    ;;
esac
