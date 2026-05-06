from __future__ import annotations

import socket
from dataclasses import dataclass

from zeroconf import ServiceInfo
from zeroconf.asyncio import AsyncZeroconf


SERVICE_TYPE = "_lonelypianist._tcp.local."


def _best_effort_local_ipv4() -> str | None:
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
    instance_name: str
    port: int
    properties: dict[bytes, bytes]

    _zc: AsyncZeroconf | None = None
    _info: ServiceInfo | None = None

    async def start(self) -> None:
        if self._zc is not None:
            return

        parsed_addresses: list[str] | None = None
        ip = _best_effort_local_ipv4()
        if ip is not None:
            parsed_addresses = [ip]

        self._zc = AsyncZeroconf()
        self._info = ServiceInfo(
            SERVICE_TYPE,
            f"{self.instance_name}.{SERVICE_TYPE}",
            port=self.port,
            properties=self.properties,
            server=f"{socket.gethostname()}.local.",
            parsed_addresses=parsed_addresses,
        )
        await self._zc.async_register_service(self._info)

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
