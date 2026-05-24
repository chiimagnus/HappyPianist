from __future__ import annotations

SERVICE_TYPE = "_lpduet._tcp.local."
DEFAULT_PORT = 8766

INSTANCE_NAME = "LonelyPianist AI Duet Server"

DEBUG_ENV_KEY = "DUET_DEBUG"

TXT_RECORD: dict[bytes, bytes] = {
    b"path": b"/generate",
    b"protocol_version": b"1",
}
