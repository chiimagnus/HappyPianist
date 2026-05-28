from __future__ import annotations

import socket
from dataclasses import dataclass

from zeroconf import ServiceInfo
from zeroconf.asyncio import AsyncZeroconf


def local_hostname_fqdn() -> str:
    raw = socket.gethostname().rstrip(".")
    if raw.endswith(".local"):
        return f"{raw}."
    return f"{raw}.local."


def sanitize_dns_sd_instance_name(name: str, *, fallback: str = "LonelyPianist Server") -> str:
    # DNS-SD "instance name" is encoded as a single DNS label.
    # Dots would split the label, so normalize them away.
    cleaned = " ".join(name.replace(".", " ").split()).strip()
    if cleaned == "":
        cleaned = fallback

    # A DNS label is limited to 63 bytes. Keep it simple and clamp by UTF-8 bytes.
    encoded = cleaned.encode("utf-8")
    if len(encoded) <= 63:
        return cleaned

    # Best-effort truncate while staying valid UTF-8.
    truncated = encoded[:63]
    while truncated:
        try:
            return truncated.decode("utf-8")
        except UnicodeDecodeError:
            truncated = truncated[:-1]
    return fallback


def best_effort_local_ipv4() -> str | None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Best-effort: no packets are sent; connect only selects the route/interface.
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        if ip and not ip.startswith("127."):
            return ip
        return None
    except OSError:
        return None
    finally:
        try:
            sock.close()
        except OSError:
            pass


@dataclass
class BonjourServiceBroadcaster:
    service_type: str
    instance_name: str
    port: int
    properties: dict[bytes, bytes]

    _zc: AsyncZeroconf | None = None
    _info: ServiceInfo | None = None

    async def start(self) -> None:
        if self._zc is not None:
            return

        parsed_addresses: list[str] | None = None
        ip = best_effort_local_ipv4()
        if ip is not None:
            parsed_addresses = [ip]

        instance = sanitize_dns_sd_instance_name(self.instance_name)
        service_type = self.service_type.rstrip(".")
        if service_type.endswith(".local"):
            service_type = f"{service_type}."
        else:
            service_type = f"{service_type}.local."

        self._zc = AsyncZeroconf()
        self._info = ServiceInfo(
            service_type,
            f"{instance}.{service_type}",
            port=self.port,
            properties=self.properties,
            server=local_hostname_fqdn(),
            parsed_addresses=parsed_addresses,
        )
        await self._zc.async_register_service(self._info, allow_name_change=True)

    async def stop(self) -> None:
        if self._zc is None:
            return

        try:
            if self._info is not None:
                try:
                    await self._zc.async_unregister_service(self._info)
                except Exception:
                    pass
        finally:
            try:
                await self._zc.async_close()
            except Exception:
                pass

            self._zc = None
            self._info = None
