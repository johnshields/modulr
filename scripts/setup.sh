#!/bin/bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew required — install from https://brew.sh, then re-run."
  exit 1
fi

brew install python ffmpeg

PIP="pip3 install --break-system-packages"
$PIP cython numpy
$PIP madmom librosa mutagen essentia

echo "Dependencies installed. Run: bash scripts/run.sh --install"
