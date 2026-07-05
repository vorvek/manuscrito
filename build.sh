#!/usr/bin/env sh
set -eu
mkdir -p build
${CC:-cc} -c src/vendor/tinyfiledialogs/tinyfiledialogs.c -o build/tinyfiledialogs.o
odin build src -out:build/manuscrito
