#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import urllib.request


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8767)
    parser.add_argument("--model", default="Qwen/Qwen3.5-0.8B")
    args = parser.parse_args()

    payload = {
        "model": args.model,
        "state": {
            "owner": "Mia",
            "bicycle_color": "red",
        },
        "questions": {
            "color": {
                "type": "choice",
                "instructions": "What color is Mia's bicycle?",
                "criteria": {
                    "red": "The bicycle is red.",
                    "blue": "The bicycle is blue.",
                },
            }
        },
    }

    request = urllib.request.Request(
        f"http://{args.host}:{args.port}/v1/classifier",
        method="POST",
        headers={"Content-Type": "application/json"},
        data=json.dumps(payload).encode("utf-8"),
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        body = json.loads(response.read().decode("utf-8"))

    assert body["answers"]["color"]["choice"] == "red"
    assert body["usage"]["output_tokens"] == 0
    print(json.dumps(body, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
