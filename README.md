# Modulr

Open-source DJ companion for macOS. Analyse, tag, mix, master.

## Stack
Swift + SwiftUI · AVFoundation · Python (madmom, librosa, ffmpeg, mutagen)

## Build
```bash
bash scripts/run.sh --install
```
Requires `brew install python ffmpeg` and `pip3 install --break-system-packages mutagen librosa cython numpy git+https://github.com/CPJKU/madmom.git`.

## Features
- BPM + key detection (madmom CNN/RNN with librosa fallback)
- Camelot-compatible key highlighting on the active track
- Search by title, key or BPM
- Tag editor with iTunes artwork finder
- Loudness measure and match (ffmpeg volumedetect)
- Tempo + pitch bake (`asetrate` + `atempo`)
- DJ-format rename `NNN_title_KEY_BPM` with edit-order drag reorder
- Waveform, stereo meters, hover-scrub timer
- Open With integration (single-instance window)
