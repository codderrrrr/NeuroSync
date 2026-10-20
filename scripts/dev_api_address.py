"""Print the address a phone on this network should use to reach the backend.

The API base URL is compiled into each app, and a laptop's address is assigned
by DHCP: it changes whenever the machine rejoins a network or the lease
renews. An app still carrying the old one will hang until it times out,
because the request is going somewhere that does not answer.

Run this, then pass the address in:

    uv run python scripts/dev_api_address.py
    flutter run --dart-define=NEUROSYNC_API_BASE_URL=http://192.168.3.111:8000
"""

from __future__ import annotations

import socket
import sys

PORT = 8000


def _lan_address() -> str | None:
    """The address of the interface that would carry traffic off this machine.

    A UDP socket is "connected" without sending anything, so the kernel picks
    the interface the same way it would for a real request.
    """
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("192.0.2.1", 9))
        address = probe.getsockname()[0]
    except OSError:
        return None
    finally:
        probe.close()
    return address


def _is_reachable(address: str) -> bool:
    """Whether something is answering on this address and port."""
    try:
        with socket.create_connection((address, PORT), timeout=1):
            return True
    except OSError:
        return False


def main() -> int:
    address = _lan_address()
    if address is None:
        print("Could not work out this machine's network address.", file=sys.stderr)
        print("Is the network up?", file=sys.stderr)
        return 1

    url = f"http://{address}:{PORT}"
    running = _is_reachable(address)

    print(f"Lan address : {address}")
    print(f"Api base url : {url}")
    print(f"Backend     : {'answering' if running else 'not answering on this port'}")

    if not running:
        print()
        print("Nothing is listening on that port. Start it with:")
        print("    uv run uvicorn neurosync.main:app --reload --host 0.0.0.0 --port 8000")

    print()
    print("Point an app at it with:")
    print(f"    flutter run --dart-define=NEUROSYNC_API_BASE_URL={url}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
