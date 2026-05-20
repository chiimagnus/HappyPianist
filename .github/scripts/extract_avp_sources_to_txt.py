#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


MARKDOWN_SUFFIXES = {".md", ".markdown"}


@dataclass(frozen=True)
class BundleSpec:
    folder_name: str
    output_name: str


def _looks_binary(path: Path) -> bool:
    try:
        with path.open("rb") as f:
            chunk = f.read(4096)
        return b"\x00" in chunk
    except OSError:
        return True


def _iter_source_files(folder: Path) -> list[Path]:
    files: list[Path] = []
    for path in folder.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() in MARKDOWN_SUFFIXES:
            continue
        if _looks_binary(path):
            continue
        files.append(path)
    return sorted(files, key=lambda p: p.as_posix())


def _read_text(path: Path) -> str:
    # Most project files are UTF-8; replace errors to keep bundling robust.
    return path.read_text(encoding="utf-8", errors="replace")


def _bundle(folder: Path, repo_root: Path, out_path: Path) -> tuple[int, int]:
    files = _iter_source_files(folder)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with out_path.open("w", encoding="utf-8", newline="\n") as out:
        for i, file_path in enumerate(files):
            rel = file_path.relative_to(repo_root).as_posix()
            header = f"===== FILE: {rel} =====\n"
            content = _read_text(file_path)
            if i != 0:
                out.write("\n")
            out.write(header)
            out.write(content)
            if not content.endswith("\n"):
                out.write("\n")

    return (len(files), out_path.stat().st_size)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Extract LonelyPianistAVP code under ViewModels/Models/Views/Services "
            "into 4 merged .txt files in LonelyPianistAVP/ (skips Markdown)."
        )
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path.cwd(),
        help="Repo root path (default: current working directory).",
    )
    parser.add_argument(
        "--output-case",
        choices=["lower", "folder"],
        default="lower",
        help=(
            "Output file naming: "
            "'lower' -> viewmodels.txt/models.txt/views.txt/services.txt; "
            "'folder' -> ViewModels.txt/Models.txt/Views.txt/Services.txt"
        ),
    )

    args = parser.parse_args()
    repo_root: Path = args.repo_root.resolve()
    avp_root = repo_root / "LonelyPianistAVP"
    if not avp_root.is_dir():
        raise SystemExit(f"LonelyPianistAVP not found under: {repo_root}")

    specs: list[BundleSpec] = [
        BundleSpec(folder_name="ViewModels", output_name="viewmodels.txt"),
        BundleSpec(folder_name="Models", output_name="models.txt"),
        BundleSpec(folder_name="Views", output_name="views.txt"),
        BundleSpec(folder_name="Services", output_name="services.txt"),
    ]
    if args.output_case == "folder":
        specs = [
            BundleSpec(folder_name=s.folder_name, output_name=f"{s.folder_name}.txt")
            for s in specs
        ]

    total_files = 0
    for spec in specs:
        folder = avp_root / spec.folder_name
        if not folder.is_dir():
            raise SystemExit(f"Missing folder: {folder}")
        out_path = avp_root / spec.output_name
        count, bytes_written = _bundle(folder=folder, repo_root=repo_root, out_path=out_path)
        total_files += count
        print(f"Wrote {out_path.relative_to(repo_root)} ({count} files, {bytes_written} bytes)")

    print(f"Done ({total_files} files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
