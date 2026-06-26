# Modulr

Open-source DJ companion for macOS. Analyse, tag, mix.

## Stack
Swift + SwiftUI · AVFoundation · Accelerate · Python (madmom, librosa, ffmpeg, mutagen)

## Install

### Homebrew (cask)
```bash
brew install --cask johnshields/modulr/modulr
```

### From source
```bash
bash scripts/setup.sh        # one-time: brew + pip dependencies
bash scripts/run.sh --install
```

## Package a release
```bash
bash scripts/package.sh
```
Builds `dist/Modulr-<version>.dmg` and prints its `sha256` for `Casks/modulr.rb`.
Set `DEVELOPER_ID` and `NOTARY_PROFILE` to sign and notarise.

## Features
- BPM + key detection (madmom CNN/RNN with librosa fallback)
- Camelot-compatible key highlighting on the active track
- Search by title, key or BPM
- Tag editor with iTunes artwork finder
- Loudness measure and match (ffmpeg volumedetect)
- Tempo + pitch bake (`asetrate` + `atempo`)
- DJ-format rename `NNN_title_KEY_BPM` with edit-order drag reorder
- Bulk move playlist tracks into a folder via a track-picker sheet
- Rekordbox-style RGB waveform (low/mid/high mapped to red/green/blue)
- Spectrogram with frequency-energy colourmap and cutoff quality verdict
- Stereo meters, hover-scrub timer
- Follows the macOS system accent colour
- Folders sort newest-added first; playlists by track number
- Open With integration (single-instance window)

## License
MIT — see [LICENSE](LICENSE).
