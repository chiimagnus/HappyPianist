# Piano Dialogue Server

## Setup

```bash
cd piano_dialogue_server
python3.12 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt
```

## OMR (PDF/Image -> MusicXML)

- OMR output root: `out/omr/`
- Each conversion job writes to: `out/omr/<basename>-<timestamp>/`
- Job layout:
  - `input/` rendered pages or copied input image
  - `debug/` oemer debug artifacts
  - `output/score.musicxml` final output for AVP import

The OMR module lives in `omr/`. Future tasks add the CLI and converter pipeline.

## oemer checkpoints

`oemer` will auto-download model checkpoints on first conversion if the checkpoint files are missing.

- First run behavior: extra download latency before inference starts.
- Expected artifacts: `1st_model.onnx`, `1st_weights.h5`, `2nd_model.onnx`, `2nd_weights.h5`
- Default cache location: `<venv>/lib/python3.12/site-packages/oemer/checkpoints/`
  - `unet_big/1st_model.onnx`
  - `unet_big/1st_weights.h5`
  - `seg_net/2nd_model.onnx`
  - `seg_net/2nd_weights.h5`

Offline/manual install:

1. Download the 4 checkpoint files listed in `omr/CHECKPOINTS.md`.
2. Copy them into the checkpoint folders above.
3. Re-run `python -m omr.cli --input <score.pdf>`.

If checkpoint download fails at runtime, the command exits non-zero with an OMR error. Keep the generated job directory under `out/omr/` for debugging.
