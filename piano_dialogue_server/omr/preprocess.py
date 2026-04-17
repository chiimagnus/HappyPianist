from __future__ import annotations

import argparse
import shutil
from pathlib import Path

import fitz
from PIL import Image, ImageOps


SUPPORTED_IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg"}


class PreprocessError(RuntimeError):
    pass


def preprocess_input(
    input_path: Path,
    job_input_dir: Path,
    *,
    pdf_dpi: int = 300,
    normalize_photo: bool = False,
) -> list[Path]:
    source = input_path.expanduser().resolve()
    if not source.exists():
        raise PreprocessError(f"input does not exist: {source}")

    job_input_dir.mkdir(parents=True, exist_ok=True)

    if source.suffix.lower() == ".pdf":
        return render_pdf_pages(source, job_input_dir, pdf_dpi=pdf_dpi)
    if source.suffix.lower() in SUPPORTED_IMAGE_SUFFIXES:
        return copy_or_normalize_image(source, job_input_dir, normalize_photo=normalize_photo)
    raise PreprocessError(f"unsupported input type: {source.suffix}")


def render_pdf_pages(pdf_path: Path, output_dir: Path, *, pdf_dpi: int = 300) -> list[Path]:
    scale = max(72, pdf_dpi) / 72.0
    matrix = fitz.Matrix(scale, scale)
    output_paths: list[Path] = []
    try:
        with fitz.open(pdf_path) as document:
            for index, page in enumerate(document):
                pix = page.get_pixmap(matrix=matrix, alpha=False)
                output = output_dir / f"page-{index + 1:04d}.png"
                pix.save(output)
                output_paths.append(output)
    except Exception as error:  # noqa: BLE001
        raise PreprocessError(f"failed to render PDF: {pdf_path}") from error

    if not output_paths:
        raise PreprocessError(f"PDF contains no pages: {pdf_path}")
    return output_paths


def copy_or_normalize_image(image_path: Path, output_dir: Path, *, normalize_photo: bool) -> list[Path]:
    output = output_dir / f"page-0001{image_path.suffix.lower()}"
    if normalize_photo:
        try:
            with Image.open(image_path) as image:
                normalized = ImageOps.autocontrast(image.convert("L"), cutoff=1)
                normalized.save(output.with_suffix(".png"), format="PNG")
                return [output.with_suffix(".png")]
        except Exception as error:  # noqa: BLE001
            raise PreprocessError(f"failed to normalize image: {image_path}") from error

    shutil.copy2(image_path, output)
    return [output]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Preprocess score PDF/image into page images for OMR.")
    parser.add_argument("--input", required=True, type=Path, help="Input score file (.pdf/.png/.jpg/.jpeg)")
    parser.add_argument(
        "--job-input-dir",
        required=True,
        type=Path,
        help="Output directory for page images (usually <job>/input)",
    )
    parser.add_argument("--pdf-dpi", type=int, default=300, help="PDF render DPI (default: 300)")
    parser.add_argument(
        "--normalize-photo",
        action="store_true",
        help="Apply lightweight grayscale+autocontrast normalization for photo inputs",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    outputs = preprocess_input(
        args.input,
        args.job_input_dir,
        pdf_dpi=args.pdf_dpi,
        normalize_photo=args.normalize_photo,
    )
    for path in outputs:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
