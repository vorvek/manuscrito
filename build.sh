#!/usr/bin/env sh
set -eu
mkdir -p build
odin build src -out:build/manuscrito
