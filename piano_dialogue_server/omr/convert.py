from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
import warnings
from uuid import uuid4

from oemer import ete

from .preprocess import PreprocessError, preprocess_input


class OMRConvertError(RuntimeError):
    pass


@dataclass(frozen=True)
class OMRJobPaths:
    root: Path
    input_dir: Path
    debug_dir: Path
    output_dir: Path
    musicxml_path: Path


def build_job_paths(input_path: Path, output_root: Path | None = None) -> OMRJobPaths:
    root = (output_root or Path(__file__).resolve().parents[1] / "out" / "omr").resolve()
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    basename = input_path.stem or "score"
    job_root = root / f"{basename}-{timestamp}-{uuid4().hex[:8]}"
    input_dir = job_root / "input"
    debug_dir = job_root / "debug"
    output_dir = job_root / "output"
    for folder in (input_dir, debug_dir, output_dir):
        folder.mkdir(parents=True, exist_ok=True)
    return OMRJobPaths(
        root=job_root,
        input_dir=input_dir,
        debug_dir=debug_dir,
        output_dir=output_dir,
        musicxml_path=output_dir / "score.musicxml",
    )


def convert_to_musicxml(
    input_path: Path,
    *,
    output_root: Path | None = None,
    pdf_dpi: int = 300,
    normalize_photo: bool = False,
    page: int = 1,
) -> OMRJobPaths:
    source = input_path.expanduser().resolve()
    if not source.exists():
        raise OMRConvertError(f"input does not exist: {source}")
    if page < 1:
        raise OMRConvertError("page must be >= 1")

    try:
        job = build_job_paths(source, output_root=output_root)
    except OSError as error:
        raise OMRConvertError(f"failed to create output job directory under {output_root or 'default root'}") from error
    try:
        rendered_pages = preprocess_input(
            source,
            job.input_dir,
            pdf_dpi=pdf_dpi,
            normalize_photo=normalize_photo,
        )
    except PreprocessError as error:
        raise OMRConvertError(str(error)) from error

    if page > len(rendered_pages):
        raise OMRConvertError(f"requested page {page} exceeds rendered pages: {len(rendered_pages)}")
    if len(rendered_pages) > 1 and page != 1:
        raise OMRConvertError("MVP currently supports only the first page of multi-page PDFs (use --page 1)")
    if len(rendered_pages) > 1:
        warnings.warn(
            "multi-page PDF detected; MVP policy processes only page 1. Merge-pages support will be added later.",
            stacklevel=2,
        )

    selected_page = rendered_pages[page - 1]
    args = SimpleNamespace(
        img_path=str(selected_page),
        output_path=str(job.musicxml_path),
        use_tf=False,
        save_cache=False,
        without_deskew=False,
    )

    try:
        ete.clear_data()
        generated_path = Path(ete.extract(args))
    except AssertionError as error:
        # oemer's dewarp step occasionally asserts on certain pages; fall back to
        # skipping deskew/dewarp to produce a best-effort MusicXML instead of failing.
        try:
            args.without_deskew = True
            ete.clear_data()
            generated_path = Path(ete.extract(args))
        except Exception as retry_error:  # noqa: BLE001
            raise OMRConvertError(f"oemer inference failed for {selected_page}") from retry_error
    except Exception as error:  # noqa: BLE001
        raise OMRConvertError(f"oemer inference failed for {selected_page}") from error

    if not generated_path.exists():
        raise OMRConvertError(f"oemer did not produce output file: {generated_path}")

    try:
        teaser = ete.teaser()
        teaser.save(job.debug_dir / "oemer_teaser.png")
    except Exception as error:  # noqa: BLE001
        raise OMRConvertError("oemer completed but failed to write debug teaser") from error

    return job
