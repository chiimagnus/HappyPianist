#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import urllib.request


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8767)
    args = parser.parse_args()

    payload = {
        "state": {
            "held_notes_count": 0,
            "sustain_value": 0,
            "recent_ioi_median_seconds": 0.55,
            "recent_note_density_per_second": 1.0,
            "seconds_since_last_note_on": 0.2,
            "is_ai_playback_active": False,
            "user_note_on_since_ai_playback_started": False,
        }
    }

    request = urllib.request.Request(
        f"http://{args.host}:{args.port}/v1/companion-decision",
        method="POST",
        headers={"Content-Type": "application/json"},
        data=json.dumps(payload).encode("utf-8"),
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        body = json.loads(response.read().decode("utf-8"))

    assert body["model"] == "Qwen/Qwen3.5-0.8B"
    assert body["action"] in {"listen", "support", "sparse", "yield", "respond"}
    assert set(body["semantic_scores"]) == {
        "continuing",
        "finished",
        "space",
        "reasserted",
    }
    assert body["usage"]["output_tokens"] == 0
    print(json.dumps(body, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
