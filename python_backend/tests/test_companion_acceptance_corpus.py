from __future__ import annotations

import argparse
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

PYTHON_BACKEND_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_ROOT = PYTHON_BACKEND_ROOT / "scripts"
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

import companion_acceptance_corpus as corpus


class FakeExecutor:
    results: list[tuple[list[corpus.Candidate], dict[str, str] | None]] = []

    def __init__(self, *, max_workers: int) -> None:
        self.max_workers = max_workers

    def __enter__(self) -> "FakeExecutor":
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def map(
        self,
        _function: object,
        _tasks: object,
        *,
        chunksize: int,
    ) -> list[tuple[list[corpus.Candidate], dict[str, str] | None]]:
        self.chunksize = chunksize
        return self.results


class CompanionAcceptanceCorpusTests(unittest.TestCase):
    def run_main_with_results(
        self,
        results: list[tuple[list[corpus.Candidate], dict[str, str] | None]],
        output: Path,
    ) -> int:
        FakeExecutor.results = results
        args = argparse.Namespace(
            maestro_root=Path("maestro"),
            pop909_root=Path("pop909"),
            output=output,
            max_per_state_per_file=3,
            workers=1,
            include_pop909_versions=False,
        )
        with (
            patch.object(corpus, "parse_args", return_value=args),
            patch.object(corpus, "maestro_files", return_value=[Path("maestro/a.mid")]),
            patch.object(corpus, "pop909_files", return_value=[]),
            patch.object(corpus.concurrent.futures, "ProcessPoolExecutor", FakeExecutor),
        ):
            return corpus.main()

    def test_main_returns_zero_when_all_corpus_files_succeed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "index.json"
            exit_code = self.run_main_with_results([([], None)], output)
            payload = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(exit_code, 0)
        self.assertEqual(payload["errors"], [])

    def test_main_returns_nonzero_but_preserves_error_evidence(self) -> None:
        error = {
            "source": "maestro",
            "file": "maestro/a.mid",
            "error": "ValueError: broken midi",
        }
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "index.json"
            exit_code = self.run_main_with_results([([], error)], output)
            payload = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(exit_code, 1)
        self.assertEqual(payload["errors"], [error])


if __name__ == "__main__":
    unittest.main()
