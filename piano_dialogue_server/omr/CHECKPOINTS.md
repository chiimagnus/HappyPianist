# oemer checkpoints strategy

## Source and download URLs

The runtime uses `oemer` checkpoints published in the upstream release assets:

- `1st_model.onnx` — <https://github.com/BreezeWhite/oemer/releases/download/checkpoints/1st_model.onnx>
- `1st_weights.h5` — <https://github.com/BreezeWhite/oemer/releases/download/checkpoints/1st_weights.h5>
- `2nd_model.onnx` — <https://github.com/BreezeWhite/oemer/releases/download/checkpoints/2nd_model.onnx>
- `2nd_weights.h5` — <https://github.com/BreezeWhite/oemer/releases/download/checkpoints/2nd_weights.h5>

## Cache and installation path

Current MVP uses the package-default checkpoint location inside the active virtual environment:

- `<venv>/lib/python3.12/site-packages/oemer/checkpoints/unet_big/`
- `<venv>/lib/python3.12/site-packages/oemer/checkpoints/seg_net/`

`oemer` auto-downloads missing files on first run. For offline use, pre-populate these directories manually.

## Offline install checklist

1. Create the two checkpoint subdirectories if missing.
2. Download all four files from the URLs above.
3. Place files into the exact folders expected by `oemer`.
4. Run `python -m omr.cli --input <path-to-score>` to verify startup.

## Licensing and redistribution notes

- `oemer` code license: MIT (from `pip show oemer` metadata, version 0.1.5).
- Checkpoint files are hosted by the `oemer` upstream repository release assets.
- Checkpoint redistribution terms are not explicitly stated in this repository; mark as **unknown / requires confirmation** before bundling checkpoints into a distributable product.
- Productization default: keep checkpoints as first-run download unless legal review confirms redistribution rights.
