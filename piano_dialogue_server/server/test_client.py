from __future__ import annotations

import asyncio
import json
import time
from pathlib import Path

import mido
import websockets


def build_test_phrase() -> list[dict]:
    return [
        {"note": 60, "velocity": 90, "time": 0.0, "duration": 0.35},
        {"note": 62, "velocity": 90, "time": 0.4, "duration": 0.35},
        {"note": 64, "velocity": 90, "time": 0.8, "duration": 0.35},
        {"note": 67, "velocity": 95, "time": 1.2, "duration": 0.50},
        {"note": 64, "velocity": 88, "time": 1.8, "duration": 0.40},
    ]


def notes_to_midi(notes: list[dict], out_path: Path) -> None:
    midi = mido.MidiFile(ticks_per_beat=480)
    track = mido.MidiTrack()
    midi.tracks.append(track)

    tempo = mido.bpm2tempo(120)
    track.append(mido.MetaMessage("set_tempo", tempo=tempo, time=0))

    events: list[tuple[float, mido.Message]] = []
    for n in notes:
        note = int(n["note"])
        velocity = int(n.get("velocity", 80))
        start = float(n["time"])
        duration = float(n["duration"])
        end = start + max(0.01, duration)

        events.append((start, mido.Message("note_on", note=note, velocity=velocity, channel=0, time=0)))
        events.append((end, mido.Message("note_off", note=note, velocity=0, channel=0, time=0)))

    events.sort(key=lambda x: x[0])

    last_time = 0.0
    for event_time, message in events:
        delta_sec = max(0.0, event_time - last_time)
        delta_ticks = int(round(mido.second2tick(delta_sec, midi.ticks_per_beat, tempo)))
        message.time = delta_ticks
        track.append(message)
        last_time = event_time

    out_path.parent.mkdir(parents=True, exist_ok=True)
    midi.save(str(out_path))


async def main() -> None:
    uri = "ws://127.0.0.1:8765/ws"
    request = {
        "type": "generate",
        "protocol_version": 1,
        "notes": build_test_phrase(),
        "params": {"top_p": 0.95, "max_tokens": 256},
        "session_id": "test-client",
    }

    t0 = time.perf_counter()
    async with websockets.connect(uri, open_timeout=10) as ws:
        await ws.send(json.dumps(request))
        raw = await ws.recv()
    rtt_ms = int((time.perf_counter() - t0) * 1000)

    response = json.loads(raw)
    response_type = response.get("type")
    if response_type != "result":
        message = response.get("message", "<no message>")
        raise SystemExit(f"server returned {response_type!r}: {message}")

    notes = response.get("notes") or []
    latency_ms = response.get("latency_ms")

    print(f"RTT: {rtt_ms} ms")
    print(f"Inference latency_ms: {latency_ms}")
    print(f"Reply notes: {len(notes)}")

    out_path = Path(__file__).resolve().parents[1] / "out" / "server_reply.mid"
    notes_to_midi(notes, out_path)
    print(f"Wrote: {out_path}")


if __name__ == "__main__":
    asyncio.run(main())
