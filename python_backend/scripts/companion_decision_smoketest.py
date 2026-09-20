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
        "protocol_version": 2,
        "input": {
            "now_timestamp_seconds": 100.0,
            "held_notes_count": 0,
            "sustain_value": 0,
            "recent_ioi_median_seconds": 0.42,
            "recent_velocity_trend": -8.0,
            "recent_note_density_per_second": 1.1,
            "last_user_event_timestamp_seconds": 99.3,
            "last_note_on_timestamp_seconds": 99.3,
            "active_pitch_center": 60.0,
            "is_ai_playback_active": False,
            "recent_notes": [
                {
                    "midi": 67,
                    "velocity": 72,
                    "onset_seconds_ago": 1.1,
                    "duration_seconds": 0.3,
                },
                {
                    "midi": 60,
                    "velocity": 65,
                    "onset_seconds_ago": 0.7,
                    "duration_seconds": 0.35,
                },
            ],
        },
    }

    request = urllib.request.Request(
        f"http://{args.host}:{args.port}/decision",
        method="POST",
        headers={"Content-Type": "application/json"},
        data=json.dumps(payload).encode("utf-8"),
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        body = json.loads(response.read().decode("utf-8"))
    print(json.dumps(body, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
