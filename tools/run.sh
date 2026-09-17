#!/bin/sh
# Command-line tools that compile the app's physics sources directly.
#   tools/run.sh bake     regenerate Perihelion/Game/Levels.swift
#   tools/run.sh verify   check the integrator, the math and every level's proof shot
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
  *)
    echo "usage: tools/run.sh bake|verify" >&2
    exit 1
    ;;
esac
