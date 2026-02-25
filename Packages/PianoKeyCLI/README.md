# PianoKeyCLI

Swift command-line tool for rendering `.mid` files to piano `.wav` audio.

## Build

```bash
swift build --package-path Packages/PianoKeyCLI
```

## Render

```bash
swift run --package-path Packages/PianoKeyCLI pianokey-cli render \
  --input ./song.mid \
  --output ./song.wav
```

Machine-friendly output:

```bash
swift run --package-path Packages/PianoKeyCLI pianokey-cli render \
  --input ./song.mid \
  --output ./song.wav \
  --json
```

Optional flags:

- `--tail-seconds <number>`: extra release tail, default `1.5`.
- `--sample-rate <number>`: output sample rate, default `44100`.
- `--sound-bank <path>`: custom DLS/SF2 bank path.
- `--json`: machine-readable JSON output.
