from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from omr.convert import OMRConvertError, convert_to_musicxml


def count_notes(musicxml_path: Path) -> int:
    root = ET.parse(musicxml_path).getroot()
    return sum(1 for element in root.iter() if element.tag.endswith("note"))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run a minimal OMR smoke test and validate MusicXML output.")
    parser.add_argument("--input", required=True, type=Path, help="Input score file (.pdf/.png/.jpg/.jpeg)")
    parser.add_argument("--page", type=int, default=1, help="1-based page index")
    parser.add_argument("--pdf-dpi", type=int, default=300, help="PDF render DPI")
    parser.add_argument("--output-root", type=Path, default=None, help="Optional OMR output root")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        job = convert_to_musicxml(
            args.input,
            page=args.page,
            pdf_dpi=args.pdf_dpi,
            output_root=args.output_root,
        )
    except OMRConvertError as error:
        print(f"smoke test failed: {error}")
        return 1

    if not job.musicxml_path.exists():
        print(f"smoke test failed: output missing at {job.musicxml_path}")
        return 1

    note_count = count_notes(job.musicxml_path)
    if note_count <= 0:
        print(f"smoke test failed: no <note> elements in {job.musicxml_path}")
        return 1

    print(f"output={job.musicxml_path}")
    print(f"note_count={note_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
